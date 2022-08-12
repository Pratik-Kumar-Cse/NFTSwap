// SPDX-License-Identifier: None
pragma solidity ^0.8.0;

/**
 * @title OrderTypes
 * @notice This library contains order types for the LooksRare exchange.
 */
library OrderTypes {
    /**
     * @notice The order type for a Swap offer.
     */
    struct Offer {
        address payable creator; // creator of the offer
        uint8 offeredTokensAmount;// total offered tokens
        uint8 requestedTokensAmount;// total requested tokens
        address payable requestTokenOwner;// requestTokenOwner address 
        ERC20Tokens bounty;// bounty tokens data  
        uint expirationTime;// expiration time                    
        mapping(uint256 => Tokens) offeredTokens;// offered tokens data
        mapping(uint256 => Tokens) requestedTokens;// requested tokensdata 
    }

    /**
     * @notice The order type for a counter Swap offer.
     */
    struct CounterOffer {
        uint offerId; // id of the offer
        address payable creator; // creator of the offer
        uint8 offeredTokensAmount;         // total offered tokens
        uint8 requestedTokensAmount;       // total requested tokens
        address payable requestTokenOwner;            // Owner's address  
        ERC20Tokens bounty;                 // bounty tokens data
        uint expirationTime;               // expiration time                       
        mapping(uint256 => Tokens) offeredTokens;      // offered tokens data
        mapping(uint256 => Tokens) requestedTokens; // requested tokensdata
    }

    struct Tokens{
        uint256 tokenId;                    // offered token id
        address tokenAddress;               // offered token address
    }

    struct ERC20Tokens{
        address tokenAddress;               // offered token address
        int tokenAmount;                    // offered token amount
    }
    
}