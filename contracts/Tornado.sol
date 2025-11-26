// https://tornado.cash
/*
 * d888888P                                           dP              a88888b.                   dP
 *    88                                              88             d8'   `88                   88
 *    88    .d8888b. 88d888b. 88d888b. .d8888b. .d888b88 .d8888b.    88        .d8888b. .d8888b. 88d888b.
 *    88    88'  `88 88'  `88 88'  `88 88'  `88 88'  `88 88'  `88    88        88'  `88 Y8ooooo. 88'  `88
 *    88    88.  .88 88       88    88 88.  .88 88.  .88 88.  .88 dP Y8.   .88 88.  .88       88 88    88
 *    dP    `88888P' dP       dP    dP `88888P8 `88888P8 `88888P' 88  Y88888P' `88888P8 `88888P' dP    dP
 * ooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

// 导入MerklTreeWithHistory库，用于管理存款的默克尔树
import "./MerkleTreeWithHistory.sol";
// 导入OpenZeppelin的ReentrancyGuard库，用于防止重入攻击
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// 定义一个验证器接口，用于验证零知识证明
interface IVerifier {
  // verifyProof`函数检查提供的证明和输入是否有效
  function verifyProof(bytes memory _proof, uint256[6] memory _input) external returns (bool);
}

// 定义抽象合约Tornado，继承自MerkleTreeWithHistory和ReentrancyGuard
abstract contract Tornado is MerkleTreeWithHistory, ReentrancyGuard {
  // 不可变的验证器合约地址
  IVerifier public immutable verifier;
  // 交易面额，每个存款的固定金额
  uint256 public denomination;

  // 映射，用于存储已花费的nullifier哈希，防止双花
  mapping(bytes32 => bool) public nullifierHashes;
  // we store all commitments just to prevent accidental deposits with the same commitment
  // 映射，用于存储所有提交的commitment，防止使用相同的commitment进行多次存款
  mapping(bytes32 => bool) public commitments;

  // 存款事件，当用户存款时触发
  event Deposit(bytes32 indexed commitment, uint32 leafIndex, uint256 timestamp);
  // 提款事件，当用户提款时触发
  event Withdrawal(address to, bytes32 nullifierHash, address indexed relayer, uint256 fee);

  /**
    @dev The constructor
    @param _verifier the address of SNARK verifier for this contract
    @param _hasher the address of MiMC hash contract
    @param _denomination transfer amount for each deposit
    @param _merkleTreeHeight the height of deposits' Merkle Tree
  */
  /**
    @dev 构造函数
    @param _verifier 零知识证明验证器合约的地址
    @param _hasher MiMC哈希合约的地址
    @param _denomination 每次存款的固定金额
    @param _merkleTreeHeight 存款默克尔树的高度
  */
  constructor(
    IVerifier _verifier,
    IHasher _hasher,
    uint256 _denomination,
    uint32 _merkleTreeHeight
  ) MerkleTreeWithHistory(_merkleTreeHeight, _hasher) {
    require(_denomination > 0, "denomination should be greater than 0");
    verifier = _verifier;
    denomination = _denomination;
  }

  /**
    @dev Deposit funds into the contract. The caller must send (for ETH) or approve (for ERC20) value equal to or `denomination` of this instance.
    @param _commitment the note commitment, which is PedersenHash(nullifier + secret)
  */
  /**
    @dev 存款函数。调用者必须发送或授权与此实例面额相等的资金。
    @param _commitment 存款凭证，即PedersenHash(nullifier + secret)
  */
  function deposit(bytes32 _commitment) external payable nonReentrant {
    // 确保该存款凭证尚未被提交过
    require(!commitments[_commitment], "The commitment has been submitted");
    // 将存款凭证插入默克尔树
    uint32 insertedIndex = _insert(_commitment);
    // 标记该存款凭证为已提交
    commitments[_commitment] = true;
    // 处理存款（在子合约中实现）
    _processDeposit();
    // 触发存款事件
    emit Deposit(_commitment, insertedIndex, block.timestamp);
  }

  /** @dev this function is defined in a child contract */
  /** @dev 这个函数在子合约中定义 */
  function _processDeposit() internal virtual;

  /**
    @dev Withdraw a deposit from the contract. `proof` is a zkSNARK proof data, and input is an array of circuit public inputs
    `input` array consists of:
      - merkle root of all deposits in the contract
      - hash of unique deposit nullifier to prevent double spends
      - the recipient of funds
      - optional fee that goes to the transaction sender (usually a relay)
  */
  /**
    @dev 从合约中提款。`_proof`是zkSNARK证明数据，`input`是电路的公共输入数组。
    `input`数组包含：
      - 合约中所有存款的默克尔树根
      - 唯一的存款nullifier的哈希，用于防止双花
      - 资金接收人地址
      - 可选的费用，支付给交易发送者（通常是中继器）
  */
  function withdraw(
    bytes calldata _proof,
    bytes32 _root,
    bytes32 _nullifierHash,
    address payable _recipient,
    address payable _relayer,
    uint256 _fee,
    uint256 _refund
  ) external payable nonReentrant {
    // 确保费用不超过面额
    require(_fee <= denomination, "Fee exceeds transfer value");
    // 确保nullifier哈希尚未被使用
    require(!nullifierHashes[_nullifierHash], "The note has been already spent");
    // 确保提供的默克尔树根是已知的（通常是最近的一个）
    require(isKnownRoot(_root), "Cannot find your merkle root"); // Make sure to use a recent one
    // 验证零知识证明
    require(
      verifier.verifyProof(
        _proof,
        [uint256(_root), uint256(_nullifierHash), uint256(_recipient), uint256(_relayer), _fee, _refund]
      ),
      "Invalid withdraw proof"
    );
    // 标记nullifier哈希为已使用
    nullifierHashes[_nullifierHash] = true;
    // 处理提款（在子合约中实现）
    _processWithdraw(_recipient, _relayer, _fee, _refund);
    emit Withdrawal(_recipient, _nullifierHash, _relayer, _fee);
  }

  /** @dev this function is defined in a child contract */
  /** @dev 这个函数在子合约中定义 */
  function _processWithdraw(
    address payable _recipient,
    address payable _relayer,
    uint256 _fee,
    uint256 _refund
  ) internal virtual;

  /** @dev whether a note is already spent */
  /** @dev 检查一个note是否已花费 */
  function isSpent(bytes32 _nullifierHash) public view returns (bool) {
    return nullifierHashes[_nullifierHash];
  }

  /** @dev whether an array of notes is already spent */
  /** @dev 检查一个note数组是否已花费 */
  function isSpentArray(bytes32[] calldata _nullifierHashes) external view returns (bool[] memory spent) {
    spent = new bool[](_nullifierHashes.length);
    for (uint256 i = 0; i < _nullifierHashes.length; i++) {
      if (isSpent(_nullifierHashes[i])) {
        spent[i] = true;
      }
    }
  }
}
