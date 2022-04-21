// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./JaxOwnable.sol";
import "./JaxProtection.sol";
import "./JaxLibrary.sol";
import "./interface/IERC20.sol";
import "./interface/IPancakeRouter.sol";

contract JaxFarming is Initializable, JaxOwnable, JaxProtection {

    using JaxLibrary for JaxFarming;

    IPancakeRouter01 public router;
    IPancakePair public lpToken;

    IERC20 public wjxn;
    IERC20 public busd;
    IERC20 public hst;

    uint public minimum_wjxn_price; // 1e18
    uint public farm_period;
    uint public total_reward;
    uint public released_reward;

    uint public farm_start_timestamp;

    bool public is_deposit_freezed;

    uint32[] public reward_pecentages; // decimals 10

    struct Farm {
        uint lp_amount;
        uint busd_amount;
        uint reward_percentage; // 10 decimals
        uint total_reward;
        uint released_reward;
        uint start_timestamp;
        uint harvest_timestamp;
        uint end_timestamp;
        address owner;
        bool is_withdrawn;
    }

    Farm[] public farms;

    mapping(address => uint[]) public user_farms;

    event Create_Farm(uint farm_id, uint amount);
    event Harvest(uint farm_id, uint busd_amount, uint hst_amount);
    event Set_Farm_Reward_Percentage(uint period, uint percentage);
    event Set_Minimum_Wjxn_Price(uint price);
    event Freeze_Deposit(bool flag);
    event Withdraw(uint farm_id);
    event Withdraw_By_Admin(address token, uint amount);

    modifier checkZeroAddress(address account) {
        require(account != address(0x0), "Only non-zero address");
        _;
    }

    function initialize(IPancakeRouter01 _router, IERC20 _wjxn, IERC20 _busd, IERC20 _hst) external initializer 
        checkZeroAddress(address(_router)) checkZeroAddress(address(_wjxn)) checkZeroAddress(address(_busd)) checkZeroAddress(address(_hst))
    {
        router = _router;
        lpToken = IPancakePair(IPancakeFactory(router.factory()).getPair(address(_wjxn), address(_busd)));
        wjxn = _wjxn;
        busd = _busd;
        hst = _hst;

        busd.approve(address(router), type(uint).max);
        wjxn.approve(address(router), type(uint).max);
        wjxn.approve(address(hst), type(uint).max);

        minimum_wjxn_price = 1.5 * 1e18; // 1.5 USD

        farm_period = 120 days;
        total_reward = 0;
        released_reward = 0;

        reward_pecentages = [2511836715, 2496667161, 2481534217, 2466443474, 2451400580, 2436411222, 2421481115, 2406615983, 2391821545, 2377103499, 2362467505, 2347919166, 2333464017, 2319107503, 2304854963, 2290711621, 2276682560, 2262772719, 2248986870, 2235329610, 2221805348, 2208418296, 2195172456, 2182071615, 2169119336, 2156318952, 2143673563, 2131186031, 2118858977, 2106694784, 2094695590, 2082863297, 2071199569, 2059705834, 2048383291, 2037232914, 2026255456, 2015451458, 2004821253, 1994364975, 1984082566, 1973973785, 1964038216, 1954275276, 1944684223, 1935264168, 1926014080, 1916932798, 1908019035, 1899271393, 1890688368, 1882268355, 1874009664, 1865910519, 1857969074, 1850183412, 1842551559, 1835071486, 1827741118, 1820558338, 1813520997, 1806626912, 1799873880, 1793270705, 1786814909, 1780504005, 1774335508, 1768306932, 1762415799, 1756659636, 1751035986, 1745542402, 1740176457, 1734935740, 1729817862, 1724820457, 1719941181, 1715177718, 1710527779, 1705989101, 1701559452, 1697236630, 1693018463, 1688902812, 1684887569, 1680970659, 1677150039, 1673423701, 1669789670, 1666246003, 1662790793, 1659422166, 1656138280, 1652937329, 1649817539, 1646777170, 1643814514, 1640927897, 1638115677, 1635376243, 1632708019, 1630109457, 1627579043, 1625115290, 1622716746, 1620381986, 1618109615, 1615898267, 1613746604, 1611653317, 1609617125, 1607636773, 1605711033, 1603838704, 1602018610, 1600249601, 1598530551, 1596860359, 1595237947, 1593662262, 1592132272, 1590646969, 1589205368, 1587806502, 1586449429, 1585133225, 1583856990, 1582619839, 1581420910, 1580259358, 1579134360, 1578045107, 1576990811, 1575970700, 1574984019, 1574030031, 1573108015, 1572217265, 1571357091, 1570526821, 1569725793, 1568953364, 1568208903, 1567491795, 1566801436, 1566137238, 1565498625, 1564885034, 1564295914, 1563730726, 1563188946, 1562670057, 1562173557, 1561698954, 1561245767, 1560813525, 1560401770, 1560010050, 1559637927, 1559284970, 1558950760, 1558634886, 1558336945, 1558056544, 1557793300, 1557546837, 1557316787, 1557102792, 1556904499, 1556721566, 1556553657, 1556400442, 1556261602, 1556136822, 1556025795, 1555928220, 1555843804, 1555772260, 1555713307, 1555666670, 1555632080];

        farm_start_timestamp = block.timestamp;

        is_deposit_freezed = false;

        _transferOwnership(msg.sender);
    }

    function get_apy_today() public view returns(uint) {
        uint elapsed_days = (block.timestamp - farm_start_timestamp) / 1 days;
        if(elapsed_days > 180) return reward_pecentages[180];
        return reward_pecentages[elapsed_days];
    }

    function create_farm(uint lp_amount) external {
        lpToken.transferFrom(msg.sender, address(this), lp_amount);
        (uint reserve0, uint reserve1, ) = lpToken.getReserves();
        uint busd_reserve = 0;
        if(lpToken.token0() == address(busd))
            busd_reserve = reserve0;
        else
            busd_reserve = reserve1;
        uint busd_amount = 2 * busd_reserve * lp_amount / lpToken.totalSupply();
        _create_farm(lp_amount, busd_amount);
    }

    function restake(uint farm_id) external {
        _withdraw(farm_id, true);
        Farm memory old_farm = farms[farm_id];
        (uint reserve0, uint reserve1, ) = lpToken.getReserves();
        uint busd_reserve = 0;
        if(lpToken.token0() == address(busd))
            busd_reserve = reserve0;
        else
            busd_reserve = reserve1;
        uint busd_amount = 2 * busd_reserve * old_farm.lp_amount / lpToken.totalSupply();
        _create_farm(old_farm.lp_amount, busd_amount);
    }

    function create_farm_busd(uint busd_amount) external {
        busd.transferFrom(msg.sender, address(this), busd_amount);
        uint busd_for_wjxn = busd_amount / 2;
        address[] memory path = new address[](2);
        path[0] = address(busd);
        path[1] = address(wjxn);
        uint wjxn_amount = _busd_buy_wjxn_amount(busd_for_wjxn);
        if(wjxn_amount > wjxn.balanceOf(address(this))) {
            uint[] memory amounts = JaxLibrary.swapWithPriceImpactLimit(address(router), busd_for_wjxn, 3e6, path, address(this)); // price impact 3%
            wjxn_amount = amounts[1];
        }
        (, , uint lp_amount) = 
            router.addLiquidity(path[0], path[1], busd_amount - busd_for_wjxn, wjxn_amount, 0, 0, address(this), block.timestamp);
        _create_farm(lp_amount, busd_amount);
        _add_liquidity();
    }

    function _add_liquidity() internal {
        uint busd_balance = busd.balanceOf(address(this));
        uint wjxn_balance = wjxn.balanceOf(address(this));
        if(busd_balance < 10000 * 1e18 || wjxn_balance == 0)
            return;
        address[] memory path = new address[](2);
        path[0] = address(busd);
        path[1] = address(wjxn);
        router.addLiquidity(path[0], path[1], busd_balance, wjxn_balance, 0, 0, owner, block.timestamp);
    }

    function _create_farm(uint lp_amount, uint busd_amount) internal {
        require(is_deposit_freezed == false, "Creating farm is frozen");
        Farm memory farm;
        farm.lp_amount = lp_amount;
        farm.busd_amount = busd_amount;
        farm.owner = msg.sender;
        farm.start_timestamp = block.timestamp;
        farm.reward_percentage = get_apy_today();
        farm.end_timestamp = block.timestamp + farm_period;
        farm.total_reward = busd_amount * farm.reward_percentage / 1e10;
        total_reward += farm.total_reward;
        uint hst_in_busd = hst.balanceOf(address(this)) * _get_wjxn_price() / 1e8;
        require(total_reward - released_reward <= hst_in_busd, "Reward Pool Exhausted");
        farm.harvest_timestamp = farm.start_timestamp;
        uint farm_id = farms.length;
        farms.push(farm);
        user_farms[msg.sender].push(farm_id);
        emit Create_Farm(farm_id, lp_amount);
    }

    function _busd_buy_wjxn_amount(uint busd_amount) internal view returns(uint) {
        return busd_amount / _get_wjxn_price();
    }

    function _get_wjxn_price() internal view returns(uint) {
        uint dex_price = _get_wjxn_dex_price();
        if(dex_price < minimum_wjxn_price)
            return minimum_wjxn_price;
        return dex_price;
    }

    function _get_wjxn_dex_price() internal view returns(uint) {
        address pairAddress = IPancakeFactory(router.factory()).getPair(address(wjxn), address(busd));
        (uint res0, uint res1,) = IPancakePair(pairAddress).getReserves();
        res0 *= 10 ** (18 - IERC20(IPancakePair(pairAddress).token0()).decimals());
        res1 *= 10 ** (18 - IERC20(IPancakePair(pairAddress).token1()).decimals());
        if(IPancakePair(pairAddress).token0() == address(busd)) {
            if(res1 > 0)
                return 1e18 * res0 / res1;
        } 
        else {
            if(res0 > 0)
                return 1e18 * res1 / res0;
        }
        return 0;
    }

    function get_pending_reward(uint farm_id) public view returns(uint) {
        Farm memory farm = farms[farm_id];
        if(farm.harvest_timestamp >= farm.end_timestamp) return 0;
        uint past_period = 0;
        if(block.timestamp >= farm.end_timestamp)
            past_period = farm.end_timestamp - farm.start_timestamp;
        else
            past_period = block.timestamp - farm.start_timestamp;
        uint period = farm.end_timestamp - farm.start_timestamp;
        uint reward = farm.total_reward * past_period / period; // hst stornetta
        return reward - farm.released_reward;
    }

    function harvest(uint farm_id) public {
        Farm storage farm = farms[farm_id];
        require(farm.owner == msg.sender, "Only farm owner");
        require(farm.is_withdrawn == false, "Farm is withdrawn");
        uint pending_reward_busd = get_pending_reward(farm_id);
        require(pending_reward_busd > 0, "Nothing to harvest");
        farm.released_reward += pending_reward_busd;
        released_reward += pending_reward_busd;
        uint pending_reward_hst = pending_reward_busd * 1e8 / _get_wjxn_price();
        require(hst.balanceOf(address(this)) >= pending_reward_hst, "Insufficient reward tokens");
        hst.transfer(msg.sender, pending_reward_hst);
        farm.harvest_timestamp = block.timestamp;
        emit Harvest(farm_id, pending_reward_busd, pending_reward_hst);
    }

    function get_farm_ids(address account) external view returns(uint[] memory){
        return user_farms[account];
    }

    function set_minimum_wjxn_price(uint price) external onlyOwner runProtection {
        require(price >= 1.5 * 1e18, "Minimum wjxn price should be above 1.5 USD");
        minimum_wjxn_price = price;
        emit Set_Minimum_Wjxn_Price(price);
    }

    function capacity_status() external view returns (uint) {
        if(is_deposit_freezed == false) return 0;
        uint hst_in_busd = hst.balanceOf(address(this)) * _get_wjxn_price() / 1e8;
        return 1e8 * (total_reward - released_reward) / hst_in_busd;
    }

    function withdraw(uint farm_id) external {
        _withdraw(farm_id, false);
    }

    function _withdraw(uint farm_id, bool is_restake) internal {
        require(farm_id < farms.length, "Invalid farm id");
        Farm storage farm = farms[farm_id];
        require(farm.owner == msg.sender, "Only farm owner can withdraw");
        require(farm.is_withdrawn == false, "Already withdrawn");
        require(farm.end_timestamp <= block.timestamp, "Locked");
        if(!is_restake)
            lpToken.transfer(farm.owner, farm.lp_amount);
        if(farm.total_reward > farm.released_reward)
            harvest(farm_id);
        farm.is_withdrawn = true;
        emit Withdraw(farm_id);
    }

    
    function withdrawByAdmin(address token, uint amount) external onlyOwner runProtection {
        IERC20(token).transfer(msg.sender, amount);
        emit Withdraw_By_Admin(token, amount);
    }

    function freeze_deposit(bool flag) external onlyOwner runProtection {
        is_deposit_freezed = flag;
        emit Freeze_Deposit(flag);
    }

}