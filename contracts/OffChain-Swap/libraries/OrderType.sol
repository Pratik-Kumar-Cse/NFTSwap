// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title OrderTypes
 * @notice This library contains order types for the LooksRare exchange.
 */
library OrderTypes {
    // keccak256("MakerOrder(address signer,address offerCollection,uint256 offerTokenId,address requestCollection,uint256 requestTokenId,int price,address currency,uint256 nonce,uint256 expire,bytes params)")
    bytes32 internal constant MAKER_ORDER_HASH = keccak256("MakerOrder(address signer,address offerCollection,uint256 offerTokenId,address requestCollection,uint256 requestTokenId,int price,address currency,uint256 nonce,uint256 expire,bytes params)");

    struct MakerOrder {
        address signer; // signer of the maker order
        address offerCollection; // collection address
        uint256 offerTokenId; // id of the token
        address requestCollection; // collection address
        uint256 requestTokenId; // id of the token
        int price; // price (used as )
        address currency; // currency (e.g., WETH)
        uint256 nonce; // order nonce (must be unique unless new maker order is meant to override existing one e.g., lower ask price)
        uint256 expire; // endTime in timestamp
        bytes params; // additional parameters
        uint8 v; // v: parameter (27 or 28)
        bytes32 r; // r: parameter
        bytes32 s; // s: parameter
    }

    struct TakerOrder {
        address taker; // msg.sender
        address offerCollection; // collection address
        uint256 offerTokenId; // id of the token
        address requestCollection; // collection address
        uint256 requestTokenId; // id of the token
        int price; // price (used as )
        address currency; // currency (e.g., WETH)
        bytes params; // other params (e.g., tokenId)
    }

    function hash(MakerOrder memory makerOrder) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    MAKER_ORDER_HASH,
                    makerOrder.signer,
                    makerOrder.offerCollection,
                    makerOrder.offerTokenId,
                    makerOrder.requestCollection,
                    makerOrder.requestTokenId,
                    makerOrder.price,
                    makerOrder.currency,
                    makerOrder.nonce,
                    makerOrder.expire,
                    keccak256(makerOrder.params)
                )
            );
    }
}
