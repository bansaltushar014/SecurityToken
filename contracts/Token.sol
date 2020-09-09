pragma solidity ^0.5.0;

contract Token{

  string internal _name;
  string internal _symbol;
  uint256 internal _granularity;
  uint256 internal _totalSupply;
  bool internal _migrated;

  bytes32[] internal _defaultPartitions;

  bool internal _isControllable;

  bool internal _isIssuable;

  mapping(address => bool) internal _isController;

  address[] internal _controllers;

  mapping(address => mapping(address => bool)) internal _authorizedOperator;

  mapping (address => mapping (bytes32 => mapping (address => bool))) internal _authorizedOperatorByPartition;

  // Mapping from tokenHolder to balance.
  mapping(address => uint256) internal _balances;

  mapping (address => mapping (bytes32 => uint256)) internal _balanceOfByPartition;

  mapping (address => bytes32[]) internal _partitionsOf;

  mapping (address => mapping (bytes32 => uint256)) internal _indexOfPartitionsOf;

  mapping (bytes32 => uint256) internal _indexOfTotalPartitions;

  mapping (bytes32 => uint256) internal _totalSupplyByPartition;

  bytes32[] internal _totalPartitions;

  mapping(bytes32 => mapping (address => mapping (address => uint256))) internal _allowedByPartition;

  mapping (bytes32 => mapping (address => bool)) internal _isControllerByPartition;

    constructor(
    // string memory name,
    // string memory symbol,
    // uint256 granularity,
    address[] memory controllers,
    bytes32[] memory defaultPartitions
  )
    public
  {
    _name = 'ERC1400Token';
    _symbol = 'DAU';
    _totalSupply = 0;
    //require(granularity >= 1); // Constructor Blocked - Token granularity can not be lower than 1
    _granularity = 1;

    _setControllers(controllers);

    _defaultPartitions = defaultPartitions;

    _isControllable = true;
    _isIssuable = true;
   }

    function _setControllers(address[] memory operators) internal {
        for (uint i = 0; i<_controllers.length; i++){
            _isController[_controllers[i]] = false;
        }
        for (uint j = 0; j<operators.length; j++){
            _isController[operators[j]] = true;
        }
        _controllers = operators;
  }

  // ******************* Token Information ********************
  function balanceOfByPartition(bytes32 partition, address tokenHolder) external view returns (uint256){
      return _balanceOfByPartition[tokenHolder][partition];
  }
  function partitionsOf(address tokenHolder) external view returns (bytes32[] memory){
      return _partitionsOf[tokenHolder];
  }

  // *********************** Transfers ************************
  function transferWithData(address to, uint256 value, bytes calldata data) external{
      _transferByDefaultPartitions(msg.sender, msg.sender, to, value, data);
  }
  function transferFromWithData(address from, address to, uint256 value, bytes calldata data) external{
        require(_isOperator(msg.sender, from), "58"); // 0x58	invalid operator (transfer agent)

        _transferByDefaultPartitions(msg.sender, from, to, value, data);
  }

    function _transferByDefaultPartitions(
    address operator,
    address from,
    address to,
    uint256 value,
    bytes memory data
  )
    internal
  {
    require(_defaultPartitions.length != 0, "55"); // // 0x55	funds locked (lockup period)

    uint256 _remainingValue = value;
    uint256 _localBalance;

    for (uint i = 0; i < _defaultPartitions.length; i++) {
      _localBalance = _balanceOfByPartition[from][_defaultPartitions[i]];
      if(_remainingValue <= _localBalance) {
        _transferByPartition(_defaultPartitions[i], operator, from, to, _remainingValue, data, "");
        _remainingValue = 0;
        break;
      } else if (_localBalance != 0) {
        _transferByPartition(_defaultPartitions[i], operator, from, to, _localBalance, data, "");
        _remainingValue = _remainingValue - _localBalance;
      }
    }

    require(_remainingValue == 0, "52"); // 0x52	insufficient balance
  }

  function _transferByPartition(
    bytes32 fromPartition,
    address operator,
    address from,
    address to,
    uint256 value,
    bytes memory data,
    bytes memory operatorData
  )
    internal
    returns (bytes32)
  {
    require(_balanceOfByPartition[from][fromPartition] >= value, "52"); // 0x52	insufficient balance

    bytes32 toPartition = fromPartition;

    if(operatorData.length != 0 && data.length >= 64) {
      toPartition = _getDestinationPartition(fromPartition, data);
    }



    _removeTokenFromPartition(from, fromPartition, value);
    _transferWithData(from, to, value);
    _addTokenToPartition(to, toPartition, value);



    if(toPartition != fromPartition) {

    }

    return toPartition;
  }

  function _transferWithData(
    address from,
    address to,
    uint256 value
  )
    internal
  {
    require(to != address(0), "57"); // 0x57	invalid receiver
    require(_balances[from] >= value, "52"); // 0x52	insufficient balance

    _balances[from] = _balances[from] - value;
    _balances[to] = _balances[to] + value;

  }
    function _getDestinationPartition(bytes32 fromPartition, bytes memory data) internal pure returns(bytes32 toPartition) {
    bytes32 changePartitionFlag = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    bytes32 flag;
    assembly {
      flag := mload(add(data, 32))
    }
    if(flag == changePartitionFlag) {
      assembly {
        toPartition := mload(add(data, 64))
      }
    } else {
      toPartition = fromPartition;
    }
  }
  // *************** Partition Token Transfers ****************
  function transferByPartition(bytes32 partition, address to, uint256 value, bytes calldata data) external returns (bytes32){
      return _transferByPartition(partition, msg.sender, msg.sender, to, value, data, "");
  }
  function operatorTransferByPartition(bytes32 partition, address from, address to, uint256 value, bytes calldata data, bytes calldata operatorData) external returns (bytes32){
        require(_isOperatorForPartition(partition, msg.sender, from)
      || (value <= _allowedByPartition[partition][from][msg.sender]), "53"); // 0x53	insufficient allowance

    if(_allowedByPartition[partition][from][msg.sender] >= value) {
      _allowedByPartition[partition][from][msg.sender] = _allowedByPartition[partition][from][msg.sender] - value;
    } else {
      _allowedByPartition[partition][from][msg.sender] = 0;
    }

    return _transferByPartition(partition, msg.sender, from, to, value, data, operatorData);

  }


    // ****************** Controller Operation ******************
  function isControllable() external view returns (bool){
      return _isController[msg.sender];
  }


    // ****************** Operator Management *******************
  function authorizeOperator(address operator) external{
      require(operator != msg.sender);
    _authorizedOperator[operator][msg.sender] = true;
  }
  function revokeOperator(address operator) external{
      require(operator != msg.sender);
    _authorizedOperator[operator][msg.sender] = false;
  }
  function authorizeOperatorByPartition(bytes32 partition, address operator) external{
      _authorizedOperatorByPartition[msg.sender][partition][operator] = true;
  }
  function revokeOperatorByPartition(bytes32 partition, address operator) external{
      _authorizedOperatorByPartition[msg.sender][partition][operator] = false;
  }

  // ****************** Operator Information ******************
  function isOperator(address operator, address tokenHolder) external view returns (bool){
      return _isOperator(operator, tokenHolder);
  }

  function _isOperator(address operator, address tokenHolder) internal view returns (bool) {
    return (operator == tokenHolder
      || _authorizedOperator[operator][tokenHolder]
      || (_isControllable && _isController[operator])
    );
  }

  function isOperatorForPartition(bytes32 partition, address operator, address tokenHolder) external view returns (bool){
      return _isOperatorForPartition(partition, operator, tokenHolder);

  }

  function _isOperatorForPartition(bytes32 partition, address operator, address tokenHolder) internal view returns (bool) {
    return (_isOperator(operator, tokenHolder)
       || _authorizedOperatorByPartition[tokenHolder][partition][operator]
       || (_isControllable && _isControllerByPartition[partition][operator])
     );
  }

  // ********************* Token Issuance *********************
  function isIssuable() external view returns (bool){
      return _isIssuable;
  }

  function issue(address tokenHolder, uint256 value, bytes calldata data) external{
      require(_defaultPartitions.length != 0, "55"); // 0x55	funds locked (lockup period)

      _issue(msg.sender, tokenHolder, value, data);
  }

  function _issue(address operator, address to, uint256 value, bytes memory data) internal
  {
        _totalSupply = _totalSupply + value;
        _balances[to] = _balances[to] + value;
        _addTokenToPartition(to, _defaultPartitions[0], value);
  }

  function _addTokenToPartition(address to, bytes32 partition, uint256 value) internal {
    if(value != 0) {
      if (_indexOfPartitionsOf[to][partition] == 0) {
        _partitionsOf[to].push(partition);
        _indexOfPartitionsOf[to][partition] = _partitionsOf[to].length;
      }
      _balanceOfByPartition[to][partition] = _balanceOfByPartition[to][partition] + value;

      if (_indexOfTotalPartitions[partition] == 0) {
        _totalPartitions.push(partition);
        _indexOfTotalPartitions[partition] = _totalPartitions.length;
      }
      _totalSupplyByPartition[partition] = _totalSupplyByPartition[partition] + value;
    }
  }

  function issueByPartition(bytes32 partition, address tokenHolder, uint256 value, bytes calldata data) external{
         _totalSupply = _totalSupply + value;
        _balances[tokenHolder] = _balances[tokenHolder] + value;
        _addTokenToPartition(tokenHolder, partition, value);

  }

  // ******************** Token Redemption ********************
  function redeem(uint256 value, bytes calldata data) external{
      _redeemByDefaultPartitions(msg.sender, msg.sender, value, data);
  }
  function redeemFrom(address tokenHolder, uint256 value, bytes calldata data) external{
        require(_isOperator(msg.sender, tokenHolder), "58"); // 0x58	invalid operator (transfer agent)
        _redeemByDefaultPartitions(msg.sender, tokenHolder, value, data);
  }
  function redeemByPartition(bytes32 partition, uint256 value, bytes calldata data) external{
      _redeemByPartition(partition, msg.sender, msg.sender, value, data, "");
  }
  function operatorRedeemByPartition(bytes32 partition, address tokenHolder, uint256 value, bytes calldata operatorData) external{
        require(_isOperatorForPartition(partition, msg.sender, tokenHolder), "58"); // 0x58	invalid operator (transfer agent)
        _redeemByPartition(partition, msg.sender, tokenHolder, value, "", operatorData);
  }
  function _removeTokenFromPartition(address from, bytes32 partition, uint256 value) internal {
    _balanceOfByPartition[from][partition] = _balanceOfByPartition[from][partition] - value;
    _totalSupplyByPartition[partition] = _totalSupplyByPartition[partition] - value;

    // If the total supply is zero, finds and deletes the partition.
    if(_totalSupplyByPartition[partition] == 0) {
      uint256 index1 = _indexOfTotalPartitions[partition];
      require(index1 > 0, "50"); // 0x50	transfer failure

      // move the last item into the index being vacated
      bytes32 lastValue = _totalPartitions[_totalPartitions.length - 1];
      _totalPartitions[index1 - 1] = lastValue; // adjust for 1-based indexing
      _indexOfTotalPartitions[lastValue] = index1;

      _totalPartitions.length -= 1;
      _indexOfTotalPartitions[partition] = 0;
    }

    // If the balance of the TokenHolder's partition is zero, finds and deletes the partition.
    if(_balanceOfByPartition[from][partition] == 0) {
      uint256 index2 = _indexOfPartitionsOf[from][partition];
      require(index2 > 0, "50"); // 0x50	transfer failure

      // move the last item into the index being vacated
      bytes32 lastValue = _partitionsOf[from][_partitionsOf[from].length - 1];
      _partitionsOf[from][index2 - 1] = lastValue;  // adjust for 1-based indexing
      _indexOfPartitionsOf[from][lastValue] = index2;

      _partitionsOf[from].length -= 1;
      _indexOfPartitionsOf[from][partition] = 0;
    }
  }

  function _redeem(address operator, address from, uint256 value, bytes memory data)
    internal
  {
    require(from != address(0), "56"); // 0x56	invalid sender
    require(_balances[from] >= value, "52"); // 0x52	insufficient balance

    _balances[from] = _balances[from] - value;
    _totalSupply = _totalSupply - value;

  }

  function _redeemByPartition(
    bytes32 fromPartition,
    address operator,
    address from,
    uint256 value,
    bytes memory data,
    bytes memory operatorData
  )
    internal
  {
    require(_balanceOfByPartition[from][fromPartition] >= value, "52"); // 0x52	insufficient balance

    _removeTokenFromPartition(from, fromPartition, value);
    _redeem(operator, from, value, data);

  }

  function _redeemByDefaultPartitions(
    address operator,
    address from,
    uint256 value,
    bytes memory data
  )
    internal
  {
    require(_defaultPartitions.length != 0, "55"); // 0x55	funds locked (lockup period)

    uint256 _remainingValue = value;
    uint256 _localBalance;

    for (uint i = 0; i < _defaultPartitions.length; i++) {
      _localBalance = _balanceOfByPartition[from][_defaultPartitions[i]];
      if(_remainingValue <= _localBalance) {
        _redeemByPartition(_defaultPartitions[i], operator, from, _remainingValue, data, "");
        _remainingValue = 0;
        break;
      } else {
        _redeemByPartition(_defaultPartitions[i], operator, from, _localBalance, data, "");
        _remainingValue = _remainingValue - _localBalance;
      }
    }

    require(_remainingValue == 0, "52"); // 0x52	insufficient balance
  }


}
// address[] Controller
// ["0xb5747835141b46f7C472393B31F8F5A57F74A44f"],
// bytes32[] defaultPartitions
// ["0x7265736572766564000000000000000000000000000000000000000000000000", "0x6973737565640000000000000000000000000000000000000000000000000000", "0x6c6f636b65640000000000000000000000000000000000000000000000000000"]



