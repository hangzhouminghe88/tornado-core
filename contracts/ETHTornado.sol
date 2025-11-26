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

// ETHTornado合约继承自Tornado
contract ETHTornado is Tornado {
  /**
   * @dev 构造函数
   * @param _verifier 零知识证明验证器合约的地址
   * @param _hasher MiMC哈希合约的地址
   * @param _denomination 存款的固定ETH金额
   * @param _merkleTreeHeight 默克尔树的高度
   */
  constructor(
    IVerifier _verifier,
    IHasher _hasher,
    uint256 _denomination,
    uint32 _merkleTreeHeight
  ) Tornado(_verifier, _hasher, _denomination, _merkleTreeHeight) {}

  /**
   * @dev 重写（override）了父合约的`_processDeposit`函数，用于处理ETH存款。
   * 要求发送的ETH金额必须等于合约预设的面额（denomination）。
   */
  function _processDeposit() internal override {
    // 检查调用者发送的ETH数量是否等于设定的面额
    require(msg.value == denomination, "Please send `mixDenomination` ETH along with transaction");
  }

  /**
   * @dev 重写（override）了父合约的`_processWithdraw`函数，用于处理ETH提款。
   * 将ETH转移给提款接收人，并支付中继费用（如果存在）。
   * @param _recipient 提款接收人地址
   * @param _relayer 交易中继器地址
   * @param _fee 支付给中继器的费用
   * @param _refund 退款金额（在此合约中为0）
   */
  function _processWithdraw(
    address payable _recipient,
    address payable _relayer,
    uint256 _fee,
    uint256 _refund
  ) internal override {
    // sanity checks
    // 健全性检查：确保提款时没有发送额外的ETH
    require(msg.value == 0, "Message value is supposed to be zero for ETH instance");
    // 健全性检查：确保退款金额为0，因为ETH实例不涉及退款
    require(_refund == 0, "Refund value is supposed to be zero for ETH instance");

    // 将ETH（面额 - 费用）转给接收人
    (bool success, ) = _recipient.call{ value: denomination - _fee }("");
    // 确保转账成功
    require(success, "payment to _recipient did not go thru");
    // 如果有费用，则将费用转给中继器
    if (_fee > 0) {
      (success, ) = _relayer.call{ value: _fee }("");
      // 确保转账成功
      require(success, "payment to _relayer did not go thru");
    }
  }
}
