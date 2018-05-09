pragma solidity 0.4.23;

import "zeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "zeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";
import "zeppelin-solidity/contracts/math/SafeMath.sol";
import "zeppelin-solidity/contracts/lifecycle/Pausable.sol";
import "zeppelin-solidity/contracts/ownership/Whitelist.sol";
import "zeppelin-solidity/contracts/ownership/Ownable.sol";


contract PresaleFirst is Ownable, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

////////////////////////////////////
//  events
////////////////////////////////////
    event Release(address indexed _to, uint256 _amount);
    event Refund(address indexed _to, uint256 _amount);

    event WithdrawToken(address indexed _from, uint256 _amount);
    event WithdrawEther(address indexed _from, uint256 _amount);

    event Purchase(address indexed _buyer, uint256 _price, uint256 _tokens);

    // Do not touch
    uint256 public maxcap;  // sale hardcap
    uint256 public exceed;  // indivisual hardcap
    uint256 public minimum; // indivisual softcap
    uint256 public rate;    // exchange rate

    // Umm... maybe?
    uint256 public startTime;   // sale startTime
    uint256 public endTime;     // sale endTime
    uint256 public weiRaised;   // check sale status

    // free
    address public wallet;      // wallet for withdrawal
    address public distributor; // contract for release, refund

    Whitelist public whitelist; // whitelist
    ERC20 public token;         // token

    constructor (
        //////////////////////////
        uint256 _maxcap,
        uint256 _exceed,
        uint256 _minimum,
        uint256 _rate,
        //////////////////////////
        uint256 _startTime,
        uint256 _endTime,
        //////////////////////////
        address _wallet,
        address _distributor,
        //////////////////////////
        address _whitelist,
        address _token
        //////////////////////////
    )
        public
    {
        require(_wallet != address(0), "given address is empty (_wallet)");
        require(_token != address(0), "given address is empty (_token)");
        require(_whitelist != address(0), "given address is empty (_whitelist)");
        require(_distributor != address(0), "given address is empty (_distributor)");

        maxcap = _maxcap;
        exceed = _exceed;
        minimum = _minumum;
        rate = _rate;

        startTime = _startTime;
        endTime = _endTime;
        weiRaised = 0;

        wallet = _wallet;
        distributor = _distributor;

        whitelist = Whitelist(_whitelist);
        token = ERC20(_token);
    }

    /* fallback function */
    function () external payable {
        collect();
    }

////////////////////////////////////
//  setter
////////////////////////////////////
    function setEndTime(uint256 _time) external onlyOwner {
        require(_time > now, "cannot set endTime to past");
        require(_time > startTime, "cannot set endTime before startTime");
        endTime = _time;
    }

    function setStartTime(uint256 _time) external onlyOwner {
        require(_time > now, "cannot set startTime to past");
        require(_time < endTime, "cannot set startTime after endTime");
        startTime = _time;
    }

    function setWhitelist(address _whitelist) external onlyOwner {
        require(_whitelist != address(0), "given address is empty (_whitelist)");
        whitelist = Whitelist(_whitelist);
    }

    function setDistributor(address _distributor) external onlyOwner {
        require(_distributor != address(0), "given address is empty (_distributor)");
        distributor = _distributor;
    }

    function setWallet(address _wallet) external onlyOwner {
        require(_wallet != address(0), "given address is empty (_wallet)");
        wallet = Whitelist(_wallet);
    }

////////////////////////////////////
//  collect eth
////////////////////////////////////

    mapping (address => uint256) public buyers;
    address[] public keys;

    function getKeyLength() external returns (uint256) {
        return keys.length;
    }

    /**
     * @dev collect ether from buyer
     * @param _buyer The address that tries to purchase
     */
    function collect()
        public
        payable
        whenIgnited
        whenNotPaused
    {
        require(Whitelist.whitelist[msg.sender], "current buyer is not in whitelist [buyer]");

        // prevent purchase delegation
        address buyer = msg.sender;

        preValidate(buyer);

        if(buyers[buyer] == 0) keys.push(buyer);

        uint256 (purchase, refund) = getPurchaseAmount(buyer);

        // buy
        uint256 tokenAmount = purchase.mul(rate);
        weiRaised = weiRaised.add(purchase);

        // wallet
        buyers[buyer] = buyers[buyer].add(purchase);
        emit Purchase(buyer, purchase, tokenAmount);

        // refund
        buyer.transfer(refund);
    }

////////////////////////////////////
//  util functions for collect
////////////////////////////////////

    /**
     * @dev validate current status
     * @param _buyer The address that tries to purchase
     */
    function preValidate(address _buyer) {
        require(_buyer != address(0), "given address is empty (_buyer)");
        require(buyers[_buyer].add(msg.value) > minimum, "cannot buy under minimum");
        require(buyers[_buyer] < exceed, "cannot buy over exceed");
        require(weiRaised <= maxcap, "hardcap is already filled");
    }

    /**
     * D1 = 세일총량 - 세일판매량
     * D2 = 개인최대 - 선입금량
     * 환불량 = 입금량 - MIN D1, D2
     * if 환불량 < 0
     *      return [ 다샀음! ]
     * else
     *      return [ 조금 사고 환불! ]
     */

    /**
     * @dev get amount of buyer can purchase
     * @param _buyer The address that tries to purchase
     */
    function getPurchaseAmount(address _buyer)
        private
        view
        returns (uint256, uint256)
    {
        uint256 d1 = maxcap.sub(weiRaised);
        uint256 d2 = exceed.sub(buyers[_buyer]);

        uint256 refund = msg.value.sub(min(d1, d2));

        if(refund > 0)
            return (msg.value.sub(refund) ,refund);
        else
            return (msg.value, 0);
    }

    function min(uint256 _a, uint256 _b)
        private
        view
        returns (uint256)
    {
        return (_a > _b) ? _b : _a;
    }

    /**
     * 1. 입금량 + 판매량 >= 세일 총량
     *      : 세일 총량 - 판매량 리턴
     * 2. 입금량 + 선입금량 >= 개인 최대
     *      : 개인 최대 - 선입금량 리턴
     * 3. 나머지
     *      : 입금량 리턴
     */

    /* function getPurchaseAmount(address _buyer)
        private
        view
        returns (uint256, uint256)
    {
        if(checkOver(msg.value.add(weiRaised), maxcap))
            return maxcap.sub(weiRaised);
        else if(checkOver(msg.value.add(buyers[_buyer]), exceed))
            return exceed.sub(buyers[_buyer]);
        else
            return msg.value;
    }

    function checkOver(uint256 a, uint256 b)
        private
        view
        returns (bool)
    {
        return a >= b;
    } */

////////////////////////////////////
//  finalize
////////////////////////////////////

    /**
     * @dev if sale finalized?
     */
    bool public finalized = false;

    /**
     * @dev finalize sale and withdraw everything (token, ether)
     */
    function finalize()
        public
        whenPaused
        onlyOwner
    {
        require(!finalized, "already finalized [finalized()]");
        require(weiRaised >= maxcap || now >= endTime, "sale not ended");

        // send ether and token to dev wallet
        withdrawEther();
        withdrawToken();

        finalized = true;
    }

////////////////////////////////////
//  release & release
////////////////////////////////////

    /**
     * @dev release token to buyer
     * @param _addr The address that owner want to release token
     */
    function release(address _addr)
        external
        whenPaused
        returns (bool)
    {
        require(msg.sender == distributor, "invalid sender [release()]");
        require(_addr != address(0), "given address is empty (_addr)");
        require(!finalized, "already finalized [release()]");

        if(buyers[_addr] == 0) return false;

        token.safeTransfer(_addr, buyers[_addr].mul(rate));
        emit Release(_addr, buyers[_addr].mul(rate));

        delete buyers[_addr];
        return true;
    }

    /**
     * @dev refund ether to buyer
     * @param _addr The address that owner want to refund ether
     */
    function refund(address _addr)
        external
        whenPaused
        returns (bool)
    {
        require(msg.sender == distributor, "invalid sender [refund()]");
        require(_addr != address(0), "given address is empty (_addr)");
        require(!finalized, "already finalized [refund()]");

        if(buyers[_addr] == 0) return false;

        _addr.transfer(buyers[_addr]);
        emit Refund(_addr, buyers[_addr]);

        delete buyers[_addr];
        return true;
    }

////////////////////////////////////
//  withdraw
////////////////////////////////////

    /**
     * @dev withdraw token to specific wallet
     */
    function withdrawToken()
        public
        whenPaused
        onlyOwner
    {
        token.safeTransfer(wallet, token.balanceOf(address(this)));
        emit WithdrawToken(wallet, token.balanceOf(address(this)));
    }

    /**
     * @dev withdraw ether to specific wallet
     */
    function withdrawEther()
        public
        whenPaused
        onlyOwner
    {
        wallet.transfer(address(this).balance);
        emit WithdrawEther(wallet, address(this).balance);
    }
}