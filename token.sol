// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts@4.7.3/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts@4.7.3/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts@4.7.3/access/Ownable.sol";
import "@openzeppelin/contracts@4.7.3/utils/math/SafeMath.sol";
import "@openzeppelin/contracts@4.7.3/utils/Address.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";

contract SigilToken is ERC20, ERC20Burnable, Ownable {
    using SafeMath for uint256;
    using Address for address;

    mapping(address => uint256) private _balances;
    mapping(address => bool) private _taxExemptList;
    mapping(address => mapping(address => uint256)) private _allowances;

    
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;

    uint256 public _lpFee = 10000000000000000;
    uint256 public _projectFee = 20000000000000000;
    uint256 public _feeThreshold = 5000000 * 10**18;
    bool private _addingToLiq = false;
    bool public _feesEnabled = true;
    address public immutable _projectWallet;
    address public _stakingPool = address(0);

    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    constructor() ERC20("Sigil Finance", "SIGIL") {
        _mint(msg.sender,  1000000000 * 10**18);
        _name = "Sigil Finance";
        _symbol = "SIGIL";

         IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
         // Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;

        _taxExemptList[owner()] = true;
        _taxExemptList[address(this)] = true;
        _taxExemptList[0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D] = true;
        _projectWallet = msg.sender;
        
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    function taxExempt(address account) public view returns (bool) {
        return _taxExemptList[account];
    }

    function addToTaxExemptList(address account) public onlyOwner {
        _taxExemptList[account] = true;
    }

    function contractBalance() public view returns (uint256) {
        return _balances[address(this)];
    }

    function disableFees() public onlyOwner {
        _feesEnabled = false;
    }

    function changeStakingPoolAddress(address _address) public onlyOwner {
        _stakingPool = _address;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public override virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }


    function decreaseAllowance(address spender, uint256 subtractedValue) public override virtual returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        if(_taxExemptList[to] == false && from != _stakingPool){
            require(balanceOf(to) + amount < 10000000 * 10**18, "Transfer exceeds maximum wallet size");
        }
        unchecked {
            _balances[from] = fromBalance - amount;
        }

        bool overMinTokenBalance = _balances[address(this)] >= _feeThreshold;
        if (
            overMinTokenBalance &&
            !_addingToLiq &&
            from != uniswapV2Pair
        ) {
            _addingToLiq = true;
            swapAndLiquify(_feeThreshold);
            _addingToLiq = false;
        }

        bool isTaxExempt = (_taxExemptList[from] == true && _taxExemptList[to] == true);
        
        if(from == _stakingPool || to == _stakingPool || isTaxExempt || _feesEnabled == false){
            _balances[to] += amount;
        } else {
            uint256 feeAmount =  amount * (_lpFee + _projectFee) / 10**18;
            _balances[to] += amount - feeAmount;     
            _balances[address(this)] += feeAmount;
        }
 
        
        emit Transfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal override virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal override virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal override virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal override virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    receive() payable external {}

   function swapAndLiquify(uint256 contractTokenBalance) private {

        uint256 quater = contractTokenBalance / 4;
        uint256 threeQuaters = contractTokenBalance - quater;

        uint256 initialBalance = address(this).balance;

        swapTokensForEth(threeQuaters);

        uint256 newBalance = address(this).balance - initialBalance;

        uint256 newBalanceQuater = newBalance / 3;

        addLiquidity(quater, newBalanceQuater);
        _projectWallet.call{value: newBalance - newBalanceQuater}("");

        emit SwapAndLiquify(threeQuaters / 3, newBalanceQuater, quater);

    }

    function swapTokensForEth(uint256 tokenAmount) internal {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, tokenAmount);
        _approve(address(this), uniswapV2Pair, tokenAmount);

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, 
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) internal {

        _approve(address(this), 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, tokenAmount);
        _approve(address(this), uniswapV2Pair, tokenAmount);


        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, 
            0, 
            0x000000000000000000000000000000000000dEaD,
            block.timestamp
        );
    }

}

