// SPDX-License-Identifier: MIT
// D神、瘋狗幫審計ㄇ
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./PolyApe.sol";

contract PolyChef is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. POLYs to distribute per block.
        uint256 lastRewardBlock; // Last block number that POLYs distribution occurs.
        uint256 accPolyPerShare; // Accumulated POLYs per share, times 1e12. See below.
    }
    // The POLYAPE TOKEN!
    PolyApeToken public poly;
    // Dev address.
    address public devaddr;
    // POLYAPE tokens created per block.
    uint256 public polyPerBlock;
    // Bonus muliplier for early poly makers.
    uint256 public constant BONUS_MULTIPLIER = 10;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when POLYAPE mining starts.
    uint256 public startBlock;
    uint256 public endBlock;
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        PolyApeToken _poly,
        address _devaddr,
        uint256 _polyPerBlock,
        uint256 _startBlock,
        uint256 _endBlock
    ) public {
        poly = _poly;
        devaddr = _devaddr;
        polyPerBlock = _polyPerBlock * 1041666666666666666;
        startBlock = _startBlock;
        endBlock = _endBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? (block.number > endBlock ? endBlock : block.number) : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accPolyPerShare: 0
            })
        );
    }

    // Update the given pool's POLYAPE allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function setRewardPeriod(
        uint256 _startBlock,
        uint256 _endBlock
    ) public onlyOwner {
        require(_endBlock > _startBlock, "setRewardPeriod: end block should bigger than start block");
        startBlock = _startBlock;
        endBlock = _endBlock;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        internal
        pure
        returns (uint256)
    {
        return _to.sub(_from);
    }

    // View function to see pending POLYs on frontend.
    function pendingPoly(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accPolyPerShare = pool.accPolyPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier =
                getMultiplier(pool.lastRewardBlock, block.number);
            uint256 polyReward =
                polyPerBlock.mul(multiplier).mul(pool.allocPoint).div(
                    totalAllocPoint
                );
            accPolyPerShare = accPolyPerShare.add(
                polyReward.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accPolyPerShare).div(1e12).sub(user.rewardDebt);
    }

    function poolTotal(uint256 _pid)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        return pool.lpToken.balanceOf(address(this));
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier =
            getMultiplier(pool.lastRewardBlock, block.number);
        uint256 polyReward =
            polyPerBlock.mul(multiplier).mul(pool.allocPoint).div(
                totalAllocPoint
            );
        poly.mint(address(this), polyReward);
        pool.accPolyPerShare = pool.accPolyPerShare.add(
            polyReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to PolyChef for POLYAPE allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending =
                user.amount.mul(pool.accPolyPerShare).div(1e12).sub(
                    user.rewardDebt
                );
            safePolyTransfer(msg.sender, pending);
        }
        pool.lpToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accPolyPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from PolyChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending =
            user.amount.mul(pool.accPolyPerShare).div(1e12).sub(
                user.rewardDebt
            );
        safePolyTransfer(msg.sender, pending);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accPolyPerShare).div(1e12);
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe poly transfer function, just in case if rounding error causes pool to not have enough POLYs.
    function safePolyTransfer(address _to, uint256 _amount) internal {
        uint256 polyBal = poly.balanceOf(address(this));
        if (_amount > polyBal) {
            poly.transfer(_to, polyBal);
        } else {
            poly.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }
}
