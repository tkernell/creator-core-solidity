// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./extensions/IERC721CreatorExtensionBase.sol";
import "./extensions/IERC721CreatorExtensionBurnable.sol";
import "./extensions/IERC721CreatorExtensionTokenURI.sol";
import "./permissions/IERC721CreatorMintPermissions.sol";
import "./IERC721CreatorCore.sol";

abstract contract ERC721CreatorCore is ReentrancyGuard, ERC721, IERC721CreatorCore {
    using Strings for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 _tokenCount = 0;

    // Track registered extensions data
    EnumerableSet.AddressSet private _extensions;
    EnumerableSet.AddressSet private _blacklistedExtensions;
    mapping (address => address) private _extensionPermissions;
    
    // For tracking which extension a token was minted by
    mapping (uint256 => address) internal _tokenExtension;

    // The baseURI for a given extension
    mapping (address => string) private _extensionBaseURI;
    mapping (address => bool) private _extensionBaseURIIdentical;

    // The prefix for any tokens with a uri configured
    mapping (address => string) private _extensionURIPrefix;

    // Mapping for token URIs
    mapping (uint256 => string) private _tokenURIs;

    /**
     * @dev Only allows registered extensions to call the specified function
     */
    modifier extensionRequired() {
        require(_extensions.contains(msg.sender), "ERC721Creator: Must be registered extension");
        _;
    }

    /**
     * @dev Only allows non-blacklisted extensions
     */
    modifier nonBlacklistRequired(address extension) {
        require(!_blacklistedExtensions.contains(extension), "ERC721Creator: Extension blacklisted");
        _;
    }   

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC721) returns (bool) {
        return interfaceId == type(IERC721CreatorCore).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721Creator-getExtensions}.
     */
    function getExtensions() external view override returns (address[] memory extensions) {
        extensions = new address[](_extensions.length());
        for (uint i = 0; i < _extensions.length(); i++) {
            extensions[i] = _extensions.at(i);
        }
        return extensions;
    }

    /**
     * @dev Register an extension
     */
    function _registerExtension(address extension, string calldata baseURI, bool baseURIIdentical) internal {
        require(ERC165Checker.supportsInterface(extension, type(IERC721CreatorExtensionBase).interfaceId), "ERC721Creator: Extension must implement IERC721CreatorExtensionBase");
        if (!_extensions.contains(extension)) {
            _extensionBaseURI[extension] = baseURI;
            _extensionBaseURIIdentical[extension] = baseURIIdentical;
            emit ExtensionRegistered(extension, msg.sender);
            _extensions.add(extension);
        }
    }

    /**
     * @dev Unregister an extension
     */
    function _unregisterExtension(address extension) internal {
       if (_extensions.contains(extension)) {
           emit ExtensionUnregistered(extension, msg.sender);
           _extensions.remove(extension);
       }
    }

    /**
     * @dev Blacklist an extension
     */
    function _blacklistExtension(address extension) internal {
       require(extension != address(this), "ERC721Creator: Cannot blacklist yourself");
       if (_extensions.contains(extension)) {
           emit ExtensionUnregistered(extension, msg.sender);
           _extensions.remove(extension);
       }
       if (!_blacklistedExtensions.contains(extension)) {
           emit ExtensionBlacklisted(extension, msg.sender);
           _blacklistedExtensions.add(extension);
       }
    }

    /**
     * @dev Set base token uri for an extension
     */
    function _setBaseTokenURIExtension(string calldata uri, bool identical) internal {
        _extensionBaseURI[msg.sender] = uri;
        _extensionBaseURIIdentical[msg.sender] = identical;
    }

    /**
     * @dev Set token uri prefix for an extension
     */
    function _setTokenURIPrefixExtension(string calldata prefix) internal {
        _extensionURIPrefix[msg.sender] = prefix;
    }

    /**
     * @dev Set token uri for a token of an extension
     */
    function _setTokenURIExtension(uint256 tokenId, string calldata uri) internal {
        require(_tokenExtension[tokenId] == msg.sender, "ERC721Creator: Invalid token");
        _tokenURIs[tokenId] = uri;
    }

    /**
     * @dev Set base token uri for tokens with no extension
     */
    function _setBaseTokenURI(string calldata uri) internal {
        _extensionBaseURI[address(this)] = uri;
    }

    /**
     * @dev Set token uri prefix for tokens with no extension
     */
    function _setTokenURIPrefix(string calldata prefix) internal {
        _extensionURIPrefix[address(this)] = prefix;
    }


    /**
     * @dev Set token uri for a token with no extension
     */
    function _setTokenURI(uint256 tokenId, string calldata uri) internal {
        require(_tokenExtension[tokenId] == address(this), "ERC721Creator: Invalid token");
        _tokenURIs[tokenId] = uri;
    }

    /**
     * @dev Set mint permissions for an extension
     */
    function _setMintPermissions(address extension, address permissions) internal {
        require(_extensions.contains(extension), "ERC721Creator: Invalid extension");
        require(permissions == address(0x0) || ERC165Checker.supportsInterface(permissions, type(IERC721CreatorMintPermissions).interfaceId), "ERC721Creator: Invalid address");
        if (_extensionPermissions[extension] != permissions) {
            _extensionPermissions[extension] = permissions;
            emit MintPermissionsUpdated(extension, permissions, msg.sender);
        }
    }

    /**
     * @dev Mint token with no extension
     */
    function _mintBase(address to, string memory uri) internal virtual returns(uint256 tokenId) {
        _tokenCount++;
        tokenId = _tokenCount;

        // Track the extension that minted the token
        _tokenExtension[tokenId] = address(this);

        _safeMint(to, tokenId);

        if (bytes(uri).length > 0) {
            _tokenURIs[tokenId] = uri;
        }

        return tokenId;
    }


    /**
     * @dev Mint token via extension
     */
    function _mintExtension(address to, string memory uri) internal virtual returns(uint256 tokenId) {
        _tokenCount++;
        tokenId = _tokenCount;

        if (_extensionPermissions[msg.sender] != address(0x0)) {
            IERC721CreatorMintPermissions(_extensionPermissions[msg.sender]).approveMint(msg.sender, tokenId, to);
        }

        // Track the extension that minted the token
        _tokenExtension[tokenId] = msg.sender;

        _safeMint(to, tokenId);

        if (bytes(uri).length > 0) {
            _tokenURIs[tokenId] = uri;
        }

        return tokenId;
    }
    
    /**
     * @dev See {IERC721Creator-burn}.
     */
    function burn(uint256 tokenId) public override nonReentrant virtual {
        _burn(tokenId);
    }

    function _burn(uint256 tokenId) internal override(ERC721) virtual {
        address extension = _tokenExtension[tokenId];
        address owner = ownerOf(tokenId);
         
        // Delete token origin extension tracking
        delete _tokenExtension[tokenId];

        ERC721._burn(tokenId);

        // Clear metadata (if any)
         if (bytes(_tokenURIs[tokenId]).length != 0) {
            delete _tokenURIs[tokenId];
        }
        
        // Callback to originating extension if needed
        if (extension != address(this)) {
           if (ERC165Checker.supportsInterface(extension, type(IERC721CreatorExtensionBurnable).interfaceId)) {
               IERC721CreatorExtensionBurnable(extension).onBurn(owner, tokenId);
           }
        }
    }
    
    /**
     * @dev See {IERC721Creator-tokenExtension}.
     */
    function tokenExtension(uint256 tokenId) public view virtual override returns (address extension) {
        require(_exists(tokenId), "Nonexistent token");

        extension = _tokenExtension[tokenId];

        require(extension != address(this), "ERC721Creator: No extension for token");
        require(!_blacklistedExtensions.contains(extension), "ERC721Creator: Extension blacklisted");

        return extension;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "Nonexistent token");

        address extension = _tokenExtension[tokenId];
        require(!_blacklistedExtensions.contains(extension), "ERC721Creator: Extension blacklisted");

        if (bytes(_tokenURIs[tokenId]).length != 0) {
            if (bytes(_extensionURIPrefix[extension]).length != 0) {
                return string(abi.encodePacked(_extensionURIPrefix[extension],_tokenURIs[tokenId]));
            }
            return _tokenURIs[tokenId];
        }

        if (ERC165Checker.supportsInterface(extension, type(IERC721CreatorExtensionTokenURI).interfaceId)) {
            return IERC721CreatorExtensionTokenURI(extension).tokenURI(address(this), tokenId);
        }

        if (!_extensionBaseURIIdentical[extension]) {
            return string(abi.encodePacked(_extensionBaseURI[extension], tokenId.toString()));
        } else {
            return _extensionBaseURI[extension];
        }
    }
    
}