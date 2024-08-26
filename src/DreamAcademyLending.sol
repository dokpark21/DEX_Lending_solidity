// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./DreamOracle.sol";
import "forge-std/console.sol";
import "./DSMath.sol";

contract DreamAcademyLending is IPriceOracle {
    ERC20 usdc;
    IPriceOracle oracle;

    struct borrowUSDC {
        uint256 amount;
        uint256 blockNumber;
    }

    struct depositUSDC {
        uint256 amount;
        uint256 interest;
    }

    address[] public lenders;
    mapping(address => uint256) public _depositETHs;
    mapping(address => depositUSDC) public _depositUSDCs;
    mapping(address => borrowUSDC) public _borrowUSDCs;

    uint256 totalBorrowedUSDCs;
    uint256 lastUpdateInterestBlock;
    uint256 totalUSDC;

    uint256 immutable LT = 75;
    uint256 immutable LTV = 50;
    uint256 immutable INTEREST_RATE = 1000000011568290959081926677;

    constructor(IPriceOracle _oracle, address _usdc) {
        oracle = _oracle;
        usdc = ERC20(_usdc);
    }

    function initializeLendingProtocol(address _usdc) external payable {
        usdc = ERC20(_usdc);
        usdc.transferFrom(msg.sender, address(this), msg.value);
    }

    function deposit(address token, uint256 amount) external payable {
        require(amount != 0, "Invalid amount");

        if (token == address(0x0)) {
            require(msg.value != 0, "Invalid amount");
            require(msg.value >= amount, "Invalid amount");
            _depositETHs[msg.sender] += amount;
        } else {
            require(
                usdc.allowance(msg.sender, address(this)) >= amount,
                "ERC20: insufficient allowance"
            );
            require(
                usdc.balanceOf(msg.sender) >= amount,
                "ERC20: transfer amount exceeds balance"
            );

            usdc.transferFrom(msg.sender, address(this), amount);
            _depositUSDCs[msg.sender].amount += amount;
            totalUSDC += amount;

            lenders.push(msg.sender);
        }
    }

    // only can borrow USDC
    function borrow(address token, uint256 amount) external {
        require(amount != 0, "Invalid amount");
        require(usdc.balanceOf(address(this)) >= amount, "Insufficient funds");
        require(token == address(usdc), "Invalid token");

        uint256 usdcPrice = oracle.getPrice(token);
        uint256 ethPrice = oracle.getPrice(address(0x0));
        require(usdcPrice != 0 && ethPrice != 0, "the price cannot be zero");

        _borrowUSDCs[msg.sender].amount = _calculateInterest(
            _borrowUSDCs[msg.sender].amount,
            _borrowUSDCs[msg.sender].blockNumber,
            INTEREST_RATE
        );

        _borrowUSDCs[msg.sender].blockNumber = block.number;

        uint256 collateral = _depositETHs[msg.sender];
        uint256 maxBorrow = _getMaxBorrow(collateral, usdcPrice, ethPrice);

        uint256 ableToBorrow = maxBorrow - _borrowUSDCs[msg.sender].amount;
        require(amount <= ableToBorrow, "Insufficient collateral");

        _borrowUSDCs[msg.sender].amount += amount;
        totalBorrowedUSDCs += amount;

        usdc.transfer(msg.sender, amount);
    }

    function repay(address tokenAddress, uint256 amount) external {
        require(amount != 0, "Invalid amount");
        require(tokenAddress == address(usdc), "Invalid token");

        require(
            usdc.allowance(msg.sender, address(this)) >= amount,
            "ERC20: insufficient allowance"
        );
        require(
            usdc.balanceOf(msg.sender) >= amount,
            "ERC20: transfer amount exceeds balance"
        );

        usdc.transferFrom(msg.sender, address(this), amount);
        _borrowUSDCs[msg.sender].amount -= amount;
        totalBorrowedUSDCs -= amount;
    }

    function liquidate(
        address user,
        address tokenAddress,
        uint256 amount
    ) external {
        uint256 ethPrice = oracle.getPrice(address(0x0));
        uint256 usdcPrice = oracle.getPrice(address(usdc));

        _borrowUSDCs[user].amount = _calculateInterest(
            _borrowUSDCs[user].amount,
            _borrowUSDCs[user].blockNumber,
            INTEREST_RATE
        );

        _borrowUSDCs[user].blockNumber = block.number;

        uint256 borrowValue = (_borrowUSDCs[user].amount * usdcPrice) /
            ethPrice;

        uint256 remainingCollateralValue = ((_depositETHs[user]) * LT) / 100;
        require(
            remainingCollateralValue < borrowValue,
            "Sufficient collateral"
        );
        require(
            amount == (_borrowUSDCs[user].amount * 1) / 4,
            "Invalid amount"
        );

        require(usdc.balanceOf(address(this)) >= amount, "Insufficient funds");

        _depositETHs[user] -= (amount * usdcPrice) / ethPrice;
        _borrowUSDCs[user].amount -= amount;
        totalBorrowedUSDCs -= amount;
    }

    function withdraw(address tokenAddress, uint256 amount) external {
        require(amount != 0, "Invalid amount");

        if (tokenAddress == address(0x0)) {
            require(_depositETHs[msg.sender] >= amount, "Insufficient funds");
            uint256 ethPrice = oracle.getPrice(address(0x0));
            uint256 usdcPrice = oracle.getPrice(address(usdc));

            _borrowUSDCs[msg.sender].amount = _calculateInterest(
                _borrowUSDCs[msg.sender].amount,
                _borrowUSDCs[msg.sender].blockNumber,
                INTEREST_RATE
            );

            _borrowUSDCs[msg.sender].blockNumber = block.number;

            uint256 borrowValue = (_borrowUSDCs[msg.sender].amount *
                usdcPrice) / ethPrice;

            uint256 remainingCollateralValue = ((_depositETHs[msg.sender] -
                amount) * LT) / 100;

            require(
                remainingCollateralValue >= borrowValue,
                "Insufficient collateral"
            );

            _depositETHs[msg.sender] -= amount;
            payable(msg.sender).call{value: amount}("");
        } else {
            uint256 ableToWithdraw = getAccruedSupplyAmount(address(usdc));
            require(
                usdc.balanceOf(address(this)) >= amount &&
                    ableToWithdraw >= amount,
                "Insufficient funds"
            );

            if (_depositUSDCs[msg.sender].amount < amount) {
                _depositUSDCs[msg.sender].interest -=
                    amount -
                    _depositUSDCs[msg.sender].amount;
                _depositUSDCs[msg.sender].amount = 0;
            } else {
                _depositUSDCs[msg.sender].amount -= amount;
            }

            usdc.transfer(msg.sender, amount);
        }
    }

    function getAccruedSupplyAmount(
        address token
    ) public updateDepositInterest returns (uint256) {
        if (token == address(0x0)) {
            return _depositETHs[msg.sender];
        } else {
            console.logUint(
                (_depositUSDCs[msg.sender].amount +
                    _depositUSDCs[msg.sender].interest) / 1e18
            );
            return
                _depositUSDCs[msg.sender].amount +
                _depositUSDCs[msg.sender].interest;
        }
    }

    function _getMaxBorrow(
        uint256 collateral,
        uint256 usdcPrice,
        uint256 ethPrice
    ) internal view returns (uint256) {
        uint256 currntCollateralValue = (collateral * ethPrice) / usdcPrice;
        return (currntCollateralValue * LTV) / 100;
    }

    function _calculateInterest(
        uint256 amount,
        uint256 blockNumber,
        uint256 annualInterestRate
    ) internal view returns (uint256) {
        uint256 blocks = block.number - blockNumber;

        uint256 timeInSeconds = blocks * 12;

        uint256 totalBorrow = DSMath.rmul(
            amount,
            DSMath.rpow(annualInterestRate, timeInSeconds)
        );

        return totalBorrow;
    }

    modifier updateDepositInterest() {
        uint256 beforeBorrowedUSDC = totalBorrowedUSDCs;
        uint256 currentBorrowedUSDC = _calculateInterest(
            totalBorrowedUSDCs,
            lastUpdateInterestBlock,
            INTEREST_RATE
        );

        uint256 interest = currentBorrowedUSDC - beforeBorrowedUSDC;

        for (uint256 i = 0; i < lenders.length; i++) {
            address user = lenders[i];
            _depositUSDCs[user].interest +=
                (interest * _depositUSDCs[user].amount) /
                totalUSDC;
        }
        lastUpdateInterestBlock = block.number;
        totalBorrowedUSDCs = currentBorrowedUSDC;
        _;
    }
}
