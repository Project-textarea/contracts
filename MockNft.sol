// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./Sentence.sol";

contract MockNft is ERC721, ERC721Enumerable, Ownable, ReentrancyGuard, IERC721Receiver {
    // lib
    using Strings for uint256;

    // struct
    
    // constant

    // storage
    uint256 private _counter;
    string private _basePath;

    // event

    constructor() ERC721("Merge", "MG") {
    
    }

    function mint(address to, uint256 num) public {
        for (uint256 i = 0; i < num; ++i){
            _counter++;
            _mint(to, _counter);
        }
    }

    // url
    function setBaseURI(string calldata path) public onlyOwner {
        _basePath = path;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        return string(abi.encodePacked(_basePath, tokenId.toString()));
    }

    // The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return interfaceId == type(IERC721Receiver).interfaceId || super.supportsInterface(interfaceId);
    }

    function onERC721Received(
        address ,
        address ,
        uint256 ,
        bytes calldata 
    ) external virtual override returns (bytes4){
        return this.onERC721Received.selector;
    }
}
