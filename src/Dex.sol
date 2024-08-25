// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Dex is ERC20 {
    IERC20 public tokenX;
    IERC20 public tokenY;

    constructor(
        address _tokenX,
        address _tokenY
    ) ERC20("Liquidity Provider Token", "LPT") {
        tokenX = IERC20(_tokenX);
        tokenY = IERC20(_tokenY);
    }

    function addLiquidity(
        uint256 _amountX,
        uint256 _amountY,
        uint256 _minLPreturn
    ) external returns (uint liquidity) {
        require(_amountX > 0 && _amountY > 0, "Insufficient amount");

        require(
            tokenX.allowance(msg.sender, address(this)) >= _amountX &&
                tokenY.allowance(msg.sender, address(this)) >= _amountY,
            "ERC20: insufficient allowance"
        );

        require(
            tokenX.balanceOf(msg.sender) >= _amountX &&
                tokenY.balanceOf(msg.sender) >= _amountY,
            "ERC20: transfer amount exceeds balance"
        );

        uint256 xBefore = tokenX.balanceOf(address(this));
        uint256 yBefore = tokenY.balanceOf(address(this));

        tokenX.transferFrom(msg.sender, address(this), _amountX);
        tokenY.transferFrom(msg.sender, address(this), _amountY);

        uint256 xAfter = tokenX.balanceOf(address(this));
        uint256 yAfter = tokenY.balanceOf(address(this));

        uint256 liquidityBefore = totalSupply();
        uint256 liquidityAfter;

        if (liquidityBefore == 0 || xBefore == 0 || yBefore == 0) {
            liquidityAfter = Math.sqrt(xAfter * yAfter);
        } else {
            uint256 liquidityX = (liquidityBefore * xAfter) / xBefore;
            uint256 liquidityY = (liquidityBefore * yAfter) / yBefore;

            liquidityAfter = (liquidityX < liquidityY)
                ? liquidityX
                : liquidityY;
        }

        uint256 lpAmount = liquidityAfter - liquidityBefore;

        require(lpAmount >= _minLPreturn, "Insufficient LP return");

        _mint(msg.sender, lpAmount);
        return lpAmount;
    }

    function removeLiquidity(
        uint256 _amount,
        uint256 _minTokenX,
        uint256 _minTokenY
    ) external returns (uint256 amountX, uint256 amountY) {
        uint256 lpTotal = totalSupply();

        require(lpTotal >= _amount, "Insufficient LP balance");
        uint256 balTokenX = tokenX.balanceOf(address(this));
        uint256 balTokenY = tokenY.balanceOf(address(this));

        uint256 amountX = (_amount * balTokenX) / lpTotal;
        uint256 amountY = (_amount * balTokenY) / lpTotal;

        require(
            balTokenX >= amountX && balTokenY >= amountY,
            "ERC20: transfer amount exceeds balance"
        );
        require(
            amountX >= _minTokenX && amountY >= _minTokenY,
            "Insufficient amount"
        );

        tokenX.transfer(msg.sender, amountX);
        tokenY.transfer(msg.sender, amountY);

        _burn(msg.sender, _amount);
        return (amountX, amountY);
    }

    function swap(
        uint256 _amountX,
        uint256 _amountY,
        uint256 _minReturn
    ) external returns (uint256) {
        require(_amountX == 0 || _amountY == 0, "Invalid amount");
        require(_amountX > 0 || _amountY > 0, "Insufficient amount");
        if (_amountX > 0 && _amountY == 0) {
            return _swapX(_amountX, _minReturn);
        }
        if (_amountY > 0 && _amountX == 0) {
            return _swapY(_amountY, _minReturn);
        }
    }

    function _swapX(
        uint256 _amountX,
        uint256 _minReturn
    ) internal returns (uint256) {
        require(
            tokenX.allowance(msg.sender, address(this)) >= _amountX,
            "ERC20: insufficient allowance"
        );
        require(
            tokenX.balanceOf(msg.sender) >= _amountX,
            "ERC20: transfer amount exceeds balance"
        );
        uint256 balTokenX = tokenX.balanceOf(address(this));
        uint256 balTokenY = tokenY.balanceOf(address(this));

        tokenX.transferFrom(msg.sender, address(this), _amountX);
        balTokenX += _amountX;
        uint256 amountY = (_amountX * balTokenY) / balTokenX;
        amountY = (amountY * 999) / 1000;
        require(amountY >= _minReturn, "Insufficient amount");

        tokenY.transfer(msg.sender, amountY);

        return amountY;
    }

    function _swapY(
        uint256 _amountY,
        uint256 _minReturn
    ) internal returns (uint256) {
        require(
            tokenY.allowance(msg.sender, address(this)) >= _amountY,
            "ERC20: insufficient allowance"
        );
        require(
            tokenY.balanceOf(msg.sender) >= _amountY,
            "ERC20: transfer amount exceeds balance"
        );

        uint256 balTokenX = tokenX.balanceOf(address(this));
        uint256 balTokenY = tokenY.balanceOf(address(this));

        tokenY.transferFrom(msg.sender, address(this), _amountY);
        balTokenY += _amountY;
        uint256 amountX = (_amountY * balTokenX) / balTokenY;
        amountX = (amountX * 999) / 1000;
        require(amountX >= _minReturn, "Insufficient amount");

        tokenX.transfer(msg.sender, amountX);

        return amountX;
    }
}
