// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract Droplinked is ERC1155{
    AggregatorV3Interface internal priceFeed;

    error NotApprovedSign(); 
    error OldPrice(); 
    
    // The Mint would be emitted on Minting new product
    event Mint_event(uint token_id, address recipient, uint amount);

    // PublishRequest would be emitted when a new publish request is made
    event PulishRequest(uint token_id, uint request_id);

    // AcceptRequest would be emitted when the `approve_request` function is called
    event AcceptRequest(uint request_id);

    // Cancelequest would be emitted when the `cancel_request` function is called
    event CancelRequest(uint request_id); 

    // DisapproveRequest would be emitted when the `disapprove` function is called
    event DisapproveRequest(uint request_id);

    // NFTMetadata Struct
    struct NFTMetadata {
        string ipfsUrl;
        uint price;
        uint comission;
    }
    
    // Request struct
    struct Request {
        uint token_id;
        address producer;
        address publisher;
        bool accepted;
    }

    // TokenID => ItsTotalSupply
    mapping (uint => uint) token_cnts;
 
    // Keeps the record of the minted tokens
    uint public token_cnt;

    // Keeps the record of the requests made
    uint public request_cnt;

    // Keeps record of the total_supply of the contract
    uint public total_supply;

    // The ratio Verifier for payment methods
    address public ratioVerifier;

    // The fee (*100) for Droplinked Account (ratioVerifier)
    uint public fee;

    // HolderAddress => ( TokenID => AMOUNT ) Holders
    mapping (address => mapping(uint => uint)) public holders;

    // TokenID => metadata
    mapping (uint => NFTMetadata) public metadatas;

    // RequestID => Request
    mapping (uint => Request) public requests;

    // ProducerAddress => ( TokenID => isRequested )
    mapping (address => mapping (uint => bool)) public isRequested;

    // HashOfMetadata => TokenID
    mapping (bytes32 => uint) public tokenid_by_hash;

    // PublisherAddress => ( RequestID => boolean )
    mapping (address => mapping (uint => bool)) public publishers_requests;

    // ProducerAddress => ( RequestID => boolean )
    mapping (address => mapping (uint => bool)) public producer_requests;

    // TokenID => string URI
    mapping (uint => string) uris;

    constructor(uint _fee, address ratio_verifier) ERC1155("") {
        fee = _fee;
        ratioVerifier = ratio_verifier;
        priceFeed = AggregatorV3Interface(0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada);
    }

    function getLatestPrice() public view returns (uint){
        (,int256 price,,,) = priceFeed.latestRoundData();
        return uint(price);
    }

    function uri(uint256 token_id) public view virtual override returns (string memory) {
        return uris[token_id];
    } 

    function mint(string calldata _uri, uint _price, uint _comission, uint amount) public {
        // Calculate the metadataHash using its IPFS uri, price, and comission
        bytes32 metadata_hash = keccak256(abi.encode(_uri,_price,_comission));
        // Get the TokenID from `tokenid_by_hash` by its calculated hash
        uint token_id = tokenid_by_hash[metadata_hash];
        // If NOT FOUND
        if (token_id == 0){
            // Create a new tokenID
            token_id = token_cnt + 1;
            token_cnt++;
            metadatas[token_id].ipfsUrl = _uri;
            metadatas[token_id].price = _price;
            metadatas[token_id].comission = _comission;
            holders[msg.sender][token_id] = amount;
            tokenid_by_hash[metadata_hash] = token_id;
        }
        // If FOUND
        else{
            // If uri, price and comission was the same, add the amount to it
            require(keccak256(abi.encode(metadatas[token_id].ipfsUrl)) == keccak256(abi.encode(_uri)));
            require(metadatas[token_id].price == _price);
            require(metadatas[token_id].comission == _comission);
            holders[msg.sender][token_id] += amount;
        }
        total_supply += amount;
        token_cnts[token_id] += amount;
        _mint(msg.sender, token_id, amount, "");
        uris[token_id] = _uri;
        emit URI(_uri, token_id);
        emit Mint_event(token_id, msg.sender,amount);
    }
    
    function publish_request(address producer_account, uint token_id) public{
        require(isRequested[producer_account][token_id] == false);
        uint request_id = request_cnt + 1;
        request_cnt++;
        requests[request_id].token_id = token_id;
        requests[request_id].producer = producer_account;
        requests[request_id].publisher = msg.sender;
        requests[request_id].accepted = false;
        publishers_requests[msg.sender][request_id] = true;
        producer_requests[producer_account][request_id] = true;
        isRequested[producer_account][token_id] = true;
        emit PulishRequest(token_id, request_id);
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public virtual override {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not token owner or approved"
        );
        _safeBatchTransferFrom(from, to, ids, amounts, data);
        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];
            holders[from][id] -= amount;
            holders[to][id] += amount;
        }
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public virtual override {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not token owner or approved"
        );
        _safeTransferFrom(from, to, id, amount, data);
        holders[from][id] -= amount;
        holders[to][id] += amount;
    }


    function approve_request(uint request_id) public {
        require(producer_requests[msg.sender][request_id] != false);
        requests[request_id].accepted = true;
        emit AcceptRequest(request_id);
    }

    function cancel_request(uint request_id) public {
        require(msg.sender == requests[request_cnt].publisher);
        require(requests[request_id].accepted == false);
        producer_requests[requests[request_id].producer][request_id] = false;
        publishers_requests[msg.sender][request_id] = false;
        isRequested[requests[request_id].producer][requests[request_id].token_id] = false;
        emit CancelRequest(request_id);
    }

    function disapprove(uint request_id) public {
        require(msg.sender == requests[request_id].producer);
        producer_requests[msg.sender][request_id] = false;
        publishers_requests[requests[request_id].publisher][request_id] = false;
        isRequested[requests[request_id].producer][requests[request_id].token_id] = false;
        requests[request_id].accepted = false;
        emit DisapproveRequest(request_id);
    }

    function verify_signature(uint ratio, uint _blockHeight, uint8 _v, bytes32 _r, bytes32 _s) view private{
        if(block.number>_blockHeight+10){
             revert OldPrice();
        }
        bytes32 _hashedMessage = keccak256(abi.encodePacked(ratio,_blockHeight));
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 prefixedHashMessage = keccak256(abi.encodePacked(prefix, _hashedMessage));
        address signer = ecrecover(prefixedHashMessage, _v, _r, _s);
        if (signer != ratioVerifier) {
            revert NotApprovedSign();
        }
    }

    function direct_buy(uint price, address recipient) public payable {
        uint totalAmount = (price*getLatestPrice())/1e10;
        uint droplinkedShare = (totalAmount*fee)/1e2;
        require(msg.value >= totalAmount , "Not enough tokens!");
        (bool t,) = payable(ratioVerifier).call{value : droplinkedShare}("");
        require(t , "transfer failed");
        (t,) = payable(recipient).call{ value : (totalAmount)}("");
        require(t, "tranfer failed");
    }
    
    function buy_recorded(address producer, uint token_id, uint shipping, uint tax, uint amount, uint ratio, uint _blockHeight, uint8 _v, bytes32 _r, bytes32 _s) public payable{
        require(holders[producer][token_id] >= amount, "Not enough amount to purchase");
        verify_signature(ratio, _blockHeight, _v, _r, _s);
        uint product_price = amount * metadatas[token_id].price * (10000000000000000)* ratio;
        require(msg.value >= product_price + (shipping + tax)*1000000000000000000);
        uint droplinked_share = (product_price * fee) / 10000;
        uint producer_share = (product_price + (shipping + tax)*1000000000000000000) - (droplinked_share);
        require(holders[producer][token_id] >= amount);
        payable(ratioVerifier).transfer(droplinked_share);
        payable(producer).transfer(producer_share);
        holders[msg.sender][token_id] += amount;
        holders[producer][token_id] -= amount;
    }

    function buy_affiliate(uint request_id, uint amount, uint shipping, uint tax, uint ratio, uint _blockHeight, uint8 _v, bytes32 _r, bytes32 _s) public payable{
        verify_signature(ratio, _blockHeight, _v, _r, _s);
        address prod = requests[request_id].producer;
        address publ = requests[request_id].publisher;
        uint token_id = requests[request_id].token_id;
        uint product_price = amount * metadatas[token_id].price * ratio * (10000000000000000);
        uint total_amount = product_price + (shipping + tax)*1000000000000000000;
        require(msg.value >= total_amount, "Not enough token sent!");
        require(holders[prod][token_id] >= amount , "Not enough NFTs to purchase!");
        // Calculations
        uint droplinked_share = (product_price * fee) / 10000;
        uint publisher_share = ((product_price - droplinked_share) * metadatas[token_id].comission) / 10000;
        uint producer_share = total_amount - (droplinked_share + publisher_share);
        // Money transfer
        payable(ratioVerifier).transfer(droplinked_share);
        payable(prod).transfer(producer_share);
        payable(publ).transfer(publisher_share);
        // Transfer
        holders[msg.sender][token_id] += amount;
        holders[prod][token_id] -= amount;
    }
    function totalSupply(uint256 id) public view returns (uint256){
        return token_cnts[id];
    }
}