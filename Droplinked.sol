// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0<0.9;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract simpleStorage is ERC1155{
    error NotApprovedSign(); 
    error OldPrice(); 
    
    // The Mint would be emitted on Minting new product
    event Mint(uint token_id, address recipient, uint amount, uint balance);

    // PublishRequest would be emitted when a new publish request is made
    event PulishRequest(uint token_id, uint request_id);

    // AcceptRequest would be emitted when the `approve_request` function is called
    event AcceptRequest(uint request_id);

    // Cancelequest would be emitted when the `cancel_request` function is called
    event CancelRequest(uint request_id);

    // DisapproveRequest would be emitted when the `disapprove` function is called
    event DisapproveRequest(uint request_id, uint token_id);

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
        _mint(msg.sender, token_id, amount, "");
        uris[token_id] = _uri;
        emit URI(_uri, token_id);
        emit Mint(token_id, msg.sender,amount,holders[msg.sender][token_id]);
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
    }

    function direct_buy(uint price, uint ratio, uint _blockHeight, address recipient, uint8 _v, bytes32 _r, bytes32 _s) public payable {
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
        payable(recipient).transfer(((price*ratio) / 100) * 1000000000000000000);
    }
    
    function buy_recorded(uint token_id, uint amount) public {
        
    }

    function buy_affiliate(uint request_id, uint amount) public {
        
    }
    function totalSupply() public view returns (uint){
        return token_cnt;
    }
}