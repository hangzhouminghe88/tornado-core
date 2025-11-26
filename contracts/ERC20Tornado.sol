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
// 导入Tornado抽象合约，该合约提供了匿名交易的基本框架
import "./Tornado.sol";
// 导入OpenZeppelin的IERC20接口，用于与ERC20代币进行交互
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// 导入OpenZeppelin的SafeERC20库，用于安全地处理ERC20代币操作
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// ERC20Tornado合约继承自Tornado
contract ERC20Tornado is Tornado {
  // 使用SafeERC20库来处理IERC20接口的实例
  using SafeERC20 for IERC20;
  // 不可变的ERC20代币合约地址
  IERC20 public token;

  /**
   * @dev 构造函数
   * @param _verifier 零知识证明验证器合约的地址
   * @param _hasher MiMC哈希合约的地址
   * @param _denomination 存款的固定代币金额
   * @param _merkleTreeHeight 默克尔树的高度
   * @param _token 要存入的ERC20代币合约的地址
   */
  constructor(
    IVerifier _verifier,
    IHasher _hasher,
    uint256 _denomination,
    uint32 _merkleTreeHeight,
    IERC20 _token
  ) Tornado(_verifier, _hasher, _denomination, _merkleTreeHeight) {
    // 设置ERC20代币合约地址
    token = _token;
  }

  /**
   * @dev 重写（override）了父合约的`_processDeposit`函数，用于处理ERC20代币存款。
   */
  function _processDeposit() internal override {
    // 健全性检查：确保存款时没有发送额外的ETH
    require(msg.value == 0, "ETH value is supposed to be 0 for ERC20 instance");
    // 安全地从调用者转账指定面额的代币到本合约地址
    token.safeTransferFrom(msg.sender, address(this), denomination);
  }

  /**
   * @dev 重写（override）了父合约的`_processWithdraw`函数，用于处理ERC20代币提款。
   * 将代币转移给提款接收人，支付中继费用，并处理可能的退款。
   * @param _recipient 提款接收人地址
   * @param _relayer 交易中继器地址
   * @param _fee 支付给中继器的费用
   * @param _refund 退款金额（通常是ETH）
   */
  function _processWithdraw(
    address payable _recipient,
    address payable _relayer,
    uint256 _fee,
    uint256 _refund
  ) internal override {
    // 检查收到的ETH退款金额是否正确
    require(msg.value == _refund, "Incorrect refund amount received by the contract");
    // 安全地将代币（面额 - 费用）转给接收人
    token.safeTransfer(_recipient, denomination - _fee);
    if (_fee > 0) {
    // 如果有费用，则安全地将费用代币转给中继器
      token.safeTransfer(_relayer, _fee);
    }

    // 如果存在ETH退款，则处理退款
    if (_refund > 0) {
      // 尝试将ETH退款转给接收人
      (bool success, ) = _recipient.call{ value: _refund }("");
      if (!success) {
        // let's return _refund back to the relayer
        // 如果转账失败，将ETH退款返回给中继器
        _relayer.transfer(_refund);
      }
    }
  }
}
