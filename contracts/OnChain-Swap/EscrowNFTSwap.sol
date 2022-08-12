// SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract NFTSwap is ReentrancyGuard {
    struct ListedToken {
        address owner;
        address contractAddr;
        uint tokenId;
        string description;
    }

    ListedToken[] public listedTokens;

    mapping (address => uint[]) public ownerTokens;

    // For convenience
    mapping (address => mapping (uint256 => uint)) public tokenIndexInOwnerTokens;

    struct Offer {
        address offerer;
        uint requestedIndex;
        uint offeredIndex;
        int exchangeValue;
        uint expires;
    }

    Offer[] public offers;

    event TokenListed(address indexed contractAddr, uint256 indexed tokenId, string description);
    event TokenUnlisted(address indexed contractAddr, uint256 indexed tokenId);
    event OfferMade(address requestedContractAddr, uint256 requestedTokenId, address offeredContractAddr, uint256 offeredTokenId, int exchangeValue, uint expires);
    event OfferTaken(address takenContractAddr, uint256 takenTokenId, address givenContractAddr, uint256 givenTokenId, int exchangeValue);
    event OfferCancelled(address requestedContractAddr, uint256 requestedTokenId, address offeredContractAddr, uint256 offeredTokenId, int exchangeValue, uint expires);

    constructor () {
        listedTokens.push(ListedToken({
            owner: address(0),
            contractAddr: address(0),
            tokenId: 0,
            description: ""
        }));
    }
    

    function escrowToken(address _contractAddr, uint256 _tokenId, string memory _description) external nonReentrant returns (uint) {

        uint listedTokenIndex = listedTokens.length;
        listedTokens.push(ListedToken({
            owner: msg.sender,
            contractAddr: _contractAddr,
            tokenId: _tokenId,
            description: _description
        }));

        // push returns the new length of the array, so listed token is at index-1
        uint ownerTokenIndex = ownerTokens[msg.sender].length;
        ownerTokens[msg.sender].push(listedTokenIndex - 1);
        tokenIndexInOwnerTokens[_contractAddr][_tokenId] = ownerTokenIndex - 1;

        // This requires the token to be approved which should be handled by the UI
        IERC721(_contractAddr).transferFrom(msg.sender, address(this), _tokenId);

        emit TokenListed(_contractAddr, _tokenId, _description);

        return listedTokenIndex - 1;
    }

    function withdrawToken(uint _listedTokenIndex) external nonReentrant {
        ListedToken storage withdrawnListedToken = listedTokens[_listedTokenIndex];
        require(withdrawnListedToken.owner == msg.sender);

        if (tokenIndexInOwnerTokens[withdrawnListedToken.contractAddr][withdrawnListedToken.tokenId] != ownerTokens[msg.sender].length - 1) {
            uint movedListedTokenIndex = ownerTokens[msg.sender][ownerTokens[msg.sender].length - 1];

            ownerTokens[msg.sender][tokenIndexInOwnerTokens[withdrawnListedToken.contractAddr][withdrawnListedToken.tokenId]] = movedListedTokenIndex;

            // Update moved token's index in owner tokens
            ListedToken storage movedListedToken = listedTokens[movedListedTokenIndex];
            tokenIndexInOwnerTokens[movedListedToken.contractAddr][movedListedToken.tokenId]
                = tokenIndexInOwnerTokens[withdrawnListedToken.contractAddr][withdrawnListedToken.tokenId];
        }

        ownerTokens[msg.sender].pop;
        delete tokenIndexInOwnerTokens[withdrawnListedToken.contractAddr][withdrawnListedToken.tokenId];

        IERC721(withdrawnListedToken.contractAddr).safeTransferFrom(address(this),msg.sender, withdrawnListedToken.tokenId);

        emit TokenUnlisted(withdrawnListedToken.contractAddr, withdrawnListedToken.tokenId);

        delete listedTokens[_listedTokenIndex];
    }

    // Makes an offer for the token listed at _requestedIndex for the token listed at _offeredIndex
    function makeOffer(uint _requestedIndex, uint _offeredIndex, int _exchangeValue, uint _expiresIn) external nonReentrant payable returns (uint) {
        // exchangeValue is the amount of funds which is offered part of the deal. Can be positive or negative.
        // If it's positive, the exact amount must have been send with this transaction
        require(_exchangeValue <= 0 || msg.value == uint(_exchangeValue));

        require(_exchangeValue >= 0 || msg.value == 0);

        require(_expiresIn > 0);

        ListedToken storage requestedToken = listedTokens[_requestedIndex];

        // Can not make offers to non-listed token
        require(requestedToken.owner != address(0));

        ListedToken storage offeredToken = listedTokens[_offeredIndex];

        require(offeredToken.owner == msg.sender);

        uint index = offers.length;
        offers.push(Offer({
            offerer: msg.sender,
            requestedIndex: _requestedIndex,
            offeredIndex: _offeredIndex,
            exchangeValue: _exchangeValue,
            expires: block.number + _expiresIn
        }));

        emit OfferMade(requestedToken.contractAddr, requestedToken.tokenId, offeredToken.contractAddr, offeredToken.tokenId, _exchangeValue, block.number + _expiresIn);

        return index - 1;
    }

    // Makes an offer for the token listed at _requestedIndex with the sent funds (without offering a token in return)
    function makeOfferWithFunds(uint _requestedIndex, uint _expiresIn) external nonReentrant payable returns (uint) {
        require(_expiresIn > 0);

        ListedToken storage requestedToken = listedTokens[_requestedIndex];

        // Can not make offers to delisted token
        require(requestedToken.owner != address(0));

        uint index = offers.length;
        offers.push(Offer({
            offerer: msg.sender,
            requestedIndex: _requestedIndex,
            offeredIndex: 0,                 // 0 means no token is offered (listed token id's start from 1, see constructor)
            exchangeValue: int(msg.value),   // Exchange value is equal to the amount sent
            expires: block.number + _expiresIn
        }));

        emit OfferMade(requestedToken.contractAddr, requestedToken.tokenId, address(0), 0, int(msg.value), block.number + _expiresIn);

        return index - 1;
    }

    function takeOffer(uint _offerId) external nonReentrant payable {
        Offer storage offer = offers[_offerId];
        require(offer.expires > block.number);

        // Negative exchangeValue means offerer wants to receive funds in part of the deal
        // In that case the exact amount of funds must have been send
        require(offer.exchangeValue >= 0 || msg.value == uint(-offer.exchangeValue));

        // If exchangeValue is greater than or equal to 0, no funds accepted
        require(offer.exchangeValue < 0 || msg.value == 0);

        ListedToken storage givenToken = listedTokens[offer.requestedIndex];
        require(givenToken.owner == msg.sender);

        givenToken.owner = offer.offerer;

        uint givenTokenIndex = tokenIndexInOwnerTokens[givenToken.contractAddr][givenToken.tokenId];

        ListedToken storage takenToken = listedTokens[offer.offeredIndex];

        // If this is a "cash-only" offer
        if (takenToken.owner == address(0)) {  // We are actually checking if null
            uint toBeMovedTokenIndex = ownerTokens[msg.sender].length - 1;

            if (givenTokenIndex != toBeMovedTokenIndex) {
                ownerTokens[msg.sender][givenTokenIndex] = ownerTokens[msg.sender][toBeMovedTokenIndex];

                ListedToken storage toBeMovedToken = listedTokens[ownerTokens[msg.sender][toBeMovedTokenIndex]];
                tokenIndexInOwnerTokens[toBeMovedToken.contractAddr][toBeMovedToken.tokenId] = givenTokenIndex;
            }

            ownerTokens[msg.sender].pop;

            uint newIndex = ownerTokens[offer.offerer].length;
            ownerTokens[offer.offerer].push(offer.requestedIndex);
            tokenIndexInOwnerTokens[givenToken.contractAddr][givenToken.tokenId] = newIndex;

            payable(msg.sender).transfer(uint(offer.exchangeValue));

            emit OfferTaken(address(0), 0, givenToken.contractAddr, givenToken.tokenId, offer.exchangeValue);
        } else { // Cash only offer
            takenToken.owner = msg.sender;

            uint takenTokenIndex = tokenIndexInOwnerTokens[takenToken.contractAddr][takenToken.tokenId];

            uint temp = ownerTokens[msg.sender][givenTokenIndex];
            ownerTokens[msg.sender][givenTokenIndex] = ownerTokens[offer.offerer][takenTokenIndex];
            ownerTokens[offer.offerer][takenTokenIndex] = temp;

            temp = tokenIndexInOwnerTokens[givenToken.contractAddr][givenToken.tokenId];
            tokenIndexInOwnerTokens[givenToken.contractAddr][givenToken.tokenId] =
                tokenIndexInOwnerTokens[takenToken.contractAddr][takenToken.tokenId];
            tokenIndexInOwnerTokens[takenToken.contractAddr][takenToken.tokenId] = temp;

            // Transfer exchange value if required. If the value is 0, no funds are transferred
            if (offer.exchangeValue > 0) {
                // We have positive value, meaning offerer pays
                payable(msg.sender).transfer(uint(offer.exchangeValue));
            } else if (offer.exchangeValue < 0) {
                // We have negative value, meaning offerer receives
                payable(offer.offerer).transfer(uint(-offer.exchangeValue));
            }

            emit OfferTaken(takenToken.contractAddr, takenToken.tokenId, givenToken.contractAddr, givenToken.tokenId, offer.exchangeValue);
        }

        // Remove offer since it's taken
        delete offers[_offerId];
    }

    // This does not remove the approval of the token
    function cancelOffer(uint _offerId) external nonReentrant {
        Offer storage offer = offers[_offerId];
        require(offer.offerer == msg.sender);

        // Refund to offerer if exchangeValue is greater than 0, which means offerer sent it when making the offer
        if (offer.exchangeValue > 0) {
            payable(offer.offerer).transfer(uint(offer.exchangeValue));
        }

        ListedToken storage requestedToken = listedTokens[offer.requestedIndex];
        ListedToken storage offeredToken = listedTokens[offer.offeredIndex];

        emit OfferCancelled(requestedToken.contractAddr, requestedToken.tokenId, offeredToken.contractAddr, offeredToken.tokenId, offer.exchangeValue, offer.expires);

        delete offers[_offerId];
    }
}