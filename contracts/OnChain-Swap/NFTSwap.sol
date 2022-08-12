// SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./libraries/OrderType.sol";
import "./interfaces/INFTSwap.sol";

contract NFTSwap is INFTSwap,ReentrancyGuard{

    using OrderTypes for OrderTypes.Offer;
    using OrderTypes for OrderTypes.CounterOffer;
    using OrderTypes for OrderTypes.Tokens;
    using OrderTypes for OrderTypes.ERC20Tokens;
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;

    uint public minimumTokensAmount;

    Counters.Counter private _offerIdTracker;
    Counters.Counter private _counterOfferIdTracker;
    mapping(uint => OrderTypes.Offer) public offers;
    mapping(uint => OrderTypes.CounterOffer) public counterOffers;

    bytes4 constant ERC721_INTERFACE_ID = 0x80ac58cd;

    event Claim(address indexed recepient, uint256 maticAmount, uint256 usdtAmount);

    event CancelSwap(uint256 indexed swapId);

    event SwapCreated(uint256 indexed swapId, uint256 indexed listId, address tokenContract, uint256 tokenId, uint256 time);

    event NotApprovedERC721(address indexed tokenContract, uint256 indexed tokenId);

    event NotApprovedERC20(address indexed tokenContract, uint256 indexed amount);

    event MarketplaceUpdated(address indexed newAddress, address indexed oldAddress);

    event EscrowUpdated(address indexed newAddress, address indexed oldAddress);

    event NotWhitelisted(address indexed tokenContract);

    event OfferMade(
        uint256 indexed offerId, 
        uint256 indexed swapId, 
        uint256 tokenId, 
        address tokenContract, 
        uint exchangeValue, 
        bool usdt
    );

    event Swapped(
        uint256 indexed swapId, 
        address originalContract, 
        uint256 originalId, 
        uint256 indexed offerId, 
        address swapContract, 
        uint256 swapTokenId
    );

    event CounterOffered(
        uint256 indexed offerId, 
        uint256 indexed counterOfferId, 
        address tokenContract, 
        uint256 tokenId, 
        uint exchangeValue
    );
    constructor(uint _minimumTokensAmount) {
        require(_minimumTokensAmount > 0,"Minimum tokens amount must be greater than 0");
        minimumTokensAmount = _minimumTokensAmount;
    }

    /**
     * @notice Require that the specified ID exists
     */
    modifier offerExits(uint256 offerId) {
        require(_exists(offerId,true), "offer doesn't exist");
        _;
    }

    /**
     * @notice Require that the specified ID exists
     */
    modifier counterOfferExits(uint256 counterOfferId) {
        require(_exists(counterOfferId,false), "counter offer doesn't exist");
        _;
    }

    /// used in the modifier to check if the Id's are valid
    function _exists(uint256 id,bool offerType) internal view returns(bool) {
        if(offerType){
            return offers[id].creator != address(0);
        }
        else{
            return counterOffers[id].creator != address(0);
        }
    }

    
    function createOffer(
        OrderTypes.Tokens[] memory _offeredTokens,
        OrderTypes.Tokens[] memory _requestedTokens,
        OrderTypes.ERC20Tokens memory _bounty,
        uint _expirationTime
    ) external nonReentrant payable {
        require(_offeredTokens.length <= minimumTokensAmount, "Offered tokens must be greater than minimum tokens amount");
        require(_requestedTokens.length <= minimumTokensAmount, "_requestedTokens tokens must be greater than minimum tokens amount");
        address owner;
        for(uint i = 0; i < _offeredTokens.length; i++) {
            require(_checkCollectionType(_offeredTokens[i].tokenAddress), "Offered token must be ERC721");
            owner = IERC721(_offeredTokens[i].tokenAddress).ownerOf(_offeredTokens[i].tokenId);
            require(owner == msg.sender, "Offered token must be owned by you");
        }
        address requestTokenOwner = IERC721(_requestedTokens[0].tokenAddress).ownerOf(_requestedTokens[0].tokenId);
        for(uint i = 0; i < _requestedTokens.length; i++) {
            require(_checkCollectionType(_requestedTokens[i].tokenAddress), "Requested token must be ERC721");
            require(IERC721(_requestedTokens[i].tokenAddress).ownerOf(_requestedTokens[i].tokenId) == requestTokenOwner, "Requested token must be owned by you");
        }
        require(_expirationTime > block.timestamp + 300);
        if(_bounty.tokenAddress == address(0)){
            // tokenAmount is the amount of funds which is offered part of the deal. Can be positive or negative.
            // If it's positive, the exact amount must have been send with this transaction
            require(_bounty.tokenAmount <= 0 || msg.value == uint(_bounty.tokenAmount));
            require(_bounty.tokenAmount >= 0 || msg.value == 0);
        }
        else{
            if(_bounty.tokenAmount > 0){
                IERC20(_bounty.tokenAddress).safeTransferFrom(msg.sender,address(this), uint(_bounty.tokenAmount));
            }
        }
        for(uint i = 0; i < _offeredTokens.length; i++) {
            IERC721(_offeredTokens[i].tokenAddress).safeTransferFrom(msg.sender,address(this), _offeredTokens[i].tokenId);
        }
        uint256 offerId = _offerIdTracker.current();
        OrderTypes.Offer storage offer = offers[offerId]; 
        offer.creator = payable(msg.sender);
        offer.offeredTokensAmount = uint8(_offeredTokens.length);
        offer.requestedTokensAmount = uint8(_requestedTokens.length);
        offer.requestTokenOwner = payable(requestTokenOwner);
        offer.bounty = _bounty;
        offer.expirationTime = _expirationTime;
        for(uint i = 0; i < _offeredTokens.length; i++) {
            offer.offeredTokens[i] = _offeredTokens[i];
        }
        for(uint i = 0; i < _requestedTokens.length; i++) {
            offer.requestedTokens[i] = _requestedTokens[i];
        }
        _offerIdTracker.increment();
    }

    function createCounterOffer(
        uint offerId,
        OrderTypes.Tokens[] memory _offeredTokens,
        OrderTypes.ERC20Tokens memory _bounty,
        uint _expirationTime
        ) external nonReentrant payable offerExits(offerId){
        OrderTypes.Offer storage offer = offers[offerId];
        require(offer.creator != msg.sender, "You can't make a counter offer on your own offer");
        require(offer.requestTokenOwner == msg.sender, "only the request token owner can make a counter offer");
        require(_offeredTokens.length <= minimumTokensAmount, "Offered tokens must be greater than minimum tokens amount");
        require(_expirationTime > block.timestamp + 300);
        for(uint i = 0; i < _offeredTokens.length; i++) {
            require(_checkCollectionType(_offeredTokens[i].tokenAddress), "Offered token must be ERC721");
            address owner = IERC721(_offeredTokens[i].tokenAddress).ownerOf(_offeredTokens[i].tokenId);
            require(owner == msg.sender, "Offered token must be owned by you");
        }
        if(_bounty.tokenAddress == address(0)){
            // tokenAmount is the amount of funds which is offered part of the deal. Can be positive or negative.
            // If it's positive, the exact amount must have been send with this transaction
            require(_bounty.tokenAmount <= 0 || msg.value == uint(_bounty.tokenAmount));
            require(_bounty.tokenAmount >= 0 || msg.value == 0);
        }
        else{
            if(_bounty.tokenAmount > 0){
                IERC20(_bounty.tokenAddress).safeTransferFrom(msg.sender,address(this), uint(_bounty.tokenAmount));
            }
        }
        uint counterOfferId = _counterOfferIdTracker.current();
        OrderTypes.CounterOffer storage counterOffer = counterOffers[counterOfferId];
        counterOffer.offerId = offerId;
        counterOffer.creator = payable(msg.sender);
        counterOffer.offeredTokensAmount = uint8(_offeredTokens.length);
        counterOffer.requestedTokensAmount = offer.offeredTokensAmount;
        counterOffer.requestTokenOwner = offer.creator;
        counterOffer.bounty = _bounty;
        counterOffer.expirationTime = offer.expirationTime;
        for(uint i = 0; i < offer.offeredTokensAmount; i++) {
            counterOffer.offeredTokens[i] = offer.offeredTokens[i];
        }
        _counterOfferIdTracker.increment();
    }

    // function updateCounterOffer(
    //     uint counterOfferId,
    //     OrderTypes.Tokens[] memory _offeredTokensUpdate,
    //     OrderTypes.ERC20Tokens memory _bounty,
    //     uint _expirationTime
    //     ) external nonReentrant payable offerExits(offerId){
    //     OrderTypes.CounterOffer memory counterOffer = counterOffers[counterOfferId];
    //     require(counterOffer.creator == msg.sender, "You can't update your own counter offer");
    //     require(_offeredTokensUpdate.length + counterOffer.offeredTokensAmount <= minimumTokensAmount, "Offered tokens must be greater than minimum tokens amount");
    //     require(_expirationTime > block.timestamp + 300);
    //     for(uint i = 0; i < _offeredTokensUpdate.length; i++) {
    //         require(_checkCollectionType(_offeredTokens[i].tokenAddress), "Offered token must be ERC721");
    //         owner = IERC721(_offeredTokens[i].tokenAddress).ownerOf(_offeredTokens[i].tokenId);
    //         require(owner == msg.sender, "Offered token must be owned by you");
    //     }
    //     if(_bounty.tokenAddress == address(0)){
    //         // tokenAmount is the amount of funds which is offered part of the deal. Can be positive or negative.
    //         // If it's positive, the exact amount must have been send with this transaction
    //         require(_bounty.tokenAmount <= 0 || msg.value == uint(_bounty.tokenAmount));
    //         require(_bounty.tokenAmount >= 0 || msg.value == 0);
    //     }
    //     else{
    //         if(_bounty.tokenAmount > 0){
    //             IERC20(_bounty.tokenAddress).safeTransferFrom(msg.sender,address(this), _bounty.tokenAmount);
    //         }
    //     }

    // }


    function acceptOffice(uint256 _offerId) external payable offerExits(_offerId) {
        OrderTypes.Offer storage offer = offers[_offerId];
        require(offer.creator != msg.sender, "You can't accept your own offer");
        require(offer.expirationTime > block.timestamp, "Offer has expired");
        require(offer.requestTokenOwner == msg.sender, "You can't accept your own offer");
        if(offer.bounty.tokenAmount < 0){
            _handleIncomingAmount(uint(-offer.bounty.tokenAmount), offer.bounty.tokenAddress);
            _handleOutgoingAmount(offer.creator,uint(offer.bounty.tokenAmount), offer.bounty.tokenAddress);
        }
        else if(offer.bounty.tokenAmount > 0){
            _handleOutgoingAmount(msg.sender,uint(offer.bounty.tokenAmount), offer.bounty.tokenAddress);
        }
        for(uint i = 0; i < offer.requestedTokensAmount; i++) {
            IERC721(offer.requestedTokens[i].tokenAddress).safeTransferFrom(msg.sender,offer.creator, offer.requestedTokens[i].tokenId);
        }
        for(uint i = 0; i < offer.offeredTokensAmount; i++) {
            IERC721(offer.offeredTokens[i].tokenAddress).safeTransferFrom(address(this),msg.sender, offer.offeredTokens[i].tokenId);
        }
        delete offers[_offerId];
    }


    function acceptCounterOffer(uint _offerId) external payable counterOfferExits(_offerId) {
        OrderTypes.CounterOffer storage counterOffer = counterOffers[_offerId];
        require(counterOffer.creator != msg.sender, "You can't accept your own counter offer");
        require(counterOffer.requestTokenOwner == msg.sender, "only the request token owner can accept a counter offer");
        require(counterOffer.expirationTime > block.timestamp, "Counter offer has expired");
        if(counterOffer.bounty.tokenAmount < 0){
            _handleIncomingAmount(uint(-counterOffer.bounty.tokenAmount), counterOffer.bounty.tokenAddress);
            _handleOutgoingAmount(counterOffer.creator,uint(counterOffer.bounty.tokenAmount), counterOffer.bounty.tokenAddress);
        }
        else if(counterOffer.bounty.tokenAmount > 0){
            _handleOutgoingAmount(msg.sender,uint(counterOffer.bounty.tokenAmount), counterOffer.bounty.tokenAddress);
        }
        for(uint i = 0; i < counterOffer.requestedTokensAmount; i++) {
            IERC721(counterOffer.requestedTokens[i].tokenAddress).safeTransferFrom(address(this),counterOffer.creator, counterOffer.requestedTokens[i].tokenId);
        }
        for(uint i = 0; i < counterOffer.offeredTokensAmount; i++) {
            IERC721(counterOffer.offeredTokens[i].tokenAddress).safeTransferFrom(address(this),msg.sender, counterOffer.offeredTokens[i].tokenId);
        }

    }


    function cancelOffer(uint offerId) external offerExits(offerId) {
        OrderTypes.Offer storage offer = offers[offerId];
        require(offer.creator == msg.sender, "You can't cancel your own offer");
        delete offers[offerId];
        if(offer.bounty.tokenAmount > 0){
            _handleOutgoingAmount(msg.sender,uint(offer.bounty.tokenAmount), offer.bounty.tokenAddress);
        }
        for(uint i = 0; i < offer.offeredTokensAmount; i++) {
            IERC721(offer.offeredTokens[i].tokenAddress).safeTransferFrom(address(this),msg.sender, offer.offeredTokens[i].tokenId);
        }
    }

    function cancelCounterOffer(uint counterOfferId) external counterOfferExits(counterOfferId) {
        OrderTypes.CounterOffer storage counterOffer = counterOffers[counterOfferId];
        require(counterOffer.creator == msg.sender, "You can't cancel your own counter offer");
        delete counterOffers[counterOfferId];
        if(counterOffer.bounty.tokenAmount > 0){
            _handleOutgoingAmount(msg.sender,uint(counterOffer.bounty.tokenAmount), counterOffer.bounty.tokenAddress);
        }
        for(uint i = 0; i < counterOffer.offeredTokensAmount; i++) {
            IERC721(counterOffer.offeredTokens[i].tokenAddress).safeTransferFrom(address(this),msg.sender, counterOffer.offeredTokens[i].tokenId);
        }
    }

    function _checkCollectionType(address _contract) internal view returns (bool) {
        if((IERC721(_contract).supportsInterface(ERC721_INTERFACE_ID)) == true) {
            return true;
        } 
        return false;
    }

    /**
     * @dev Given an amount and a currency, transfer the currency to this contract.
     */
    function _handleIncomingAmount(uint256 amount, address currency) internal {
        if (amount > 0) {
            // If this is an ETH bid, ensure they sent enough and convert it to WETH under the hood
            if(currency == address(0)) {
                require(msg.value == amount, "Sent ETH Value does not match specified bid amount");
            } else {
                // We must check the balance that was actually transferred to the auction,
                // as some tokens impose a transfer fee and would not actually transfer the
                // full amount to the market, resulting in potentally locked funds
                IERC20 token = IERC20(currency);
                uint256 beforeBalance = token.balanceOf(address(this));
                token.safeTransferFrom(msg.sender, address(this), amount);
                uint256 afterBalance = token.balanceOf(address(this));
                require(beforeBalance + amount == afterBalance, "Token transfer call did not transfer expected amount");
            }
        }
    }

    function _handleOutgoingAmount(
        address to,
        uint256 amount,
        address currency
    ) internal {
        if (amount > 0) {
            if(currency == address(0)) {
                require(_safeTransferETH(to, amount),"token is not transfer"); 
            } else {
                IERC20(currency).safeTransfer(to, amount);
            }
        }
    }

    function _safeTransferETH(address to, uint256 value) internal returns (bool) {
        (bool success, ) = to.call{value: value}(new bytes(0));
        return success;
    }
}