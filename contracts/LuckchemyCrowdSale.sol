pragma solidity ^0.4.15;


//import '../node_modules/zeppelin-solidity/contracts/math/SafeMath.sol';
import './LuckchemyToken.sol';


/*
 *Crowdsale contract for Luckchemy Token
*/
contract LuckchemyCrowdsale {
    using SafeMath for uint256;

    //  Token for selling
    LuckchemyToken public token;

    /*
    *  Start and End date of investment process
    */

    // 2018-04-30 00:00:00 GMT - start time for public sale
    uint256 public constant START_TIME_SALE = 1525046400;

    // 2018-07-20 23:59:59 GMT - end time for public sale
    uint256 public constant END_TIME_SALE = 1532131199;

    // 2018-04-02 00:00:00 GMT - start time for private sale
    uint256 public constant START_TIME_PRESALE = 1522627200;

    // 2018-04-24 23:59:59 GMT - end time for private sale
    uint256 public constant END_TIME_PRESALE = 1524614399;


    // amount of already sold tokens
    uint256 public tokensSold = 0;

    //supply for crowdSale
    uint256 public totalSupply = 0;
    // soft cap
    uint256 public constant softCap = 1000 ether;

    // ether representation of collected fiat
    uint256 public fiatBalance = 0;

    //address of serviceAgent (it can calls  payFiat function)
    address public serviceAgent;

    // owner of the contract
    address public owner;

    //default token rate
    uint public constant RATE = 25000; // Token price in ETH - 0.00004 ETH  1 ETHER = 25000 tokens

    // 2018/04/30 - 2018/07/22  
    uint public constant RATE_PRIVATE_PRESALE = RATE * 100 / 20; // 80 % discount

    // 2018/04/30 - 2018/07/20
    uint public constant RATE_STAGE_ONE = RATE * 100 / 60;  // 40% discount

    // 2018/04/02 - 2018/04/24   
    uint public constant RATE_STAGE_TWO = RATE * 100 / 80; // 20% discount

    // 2018/04/30 - 2018/07/22  
    uint public constant RATE_STAGE_THREE = RATE;




    //White list of addresses that are allowed to by a token
    mapping(address => bool) public whitelist;


    /**
     * List  of addresses for ICO fund with shares in %
     * 
     */
    uint public constant LOTTERY_FUND_SHARE = 40;
    uint public constant MARKETING_SHARE = 30;
    uint public constant DEVELOPMENT_SHARE = 10;
    uint public constant SUPPORT_SHARE = 10;
    uint public constant PARTNERS_SHARE = 10;

    address public constant LOTTERY_FUND_ADDRESS = 0x84137CB59076a61F3f94B2C39Da8fbCb63B6f096;
    address public constant MARKETING_ADDRESS = 0xEBBeAA0699837De527B29A03ECC914159D939Eea;
    address public constant DEVELOPMENT_ADDRESS = 0xEBBeAA0699837De527B29A03ECC914159D939Eea;
    address public constant SUPPORT_ADDRESS = 0xEBBeAA0699837De527B29A03ECC914159D939Eea;
    address public constant PARTNERS_ADDRESS = 0x820502e8c80352f6e11Ce036DF03ceeEBE002642;

    /**
     * event for token ETH purchase  logging
     * @param purchaser who paid for the tokens
     * @param beneficiary who got the tokens
     * @param value weis paid for purchase
     * @param amount amount of tokens purchased
     */
    event TokenETHPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);


    /**
     * event for token FIAT purchase  logging
     * @param purchaser who paid for the tokens
     * @param beneficiary who got the tokens
     * @param amount amount of tokens purchased
     */
    event TokenFiatPurchase(address indexed purchaser, address indexed beneficiary, uint256 amount);

    /*
     * modifier which gives specific rights to owner
     */
    modifier onlyOwner(){
        require(msg.sender == owner);
        _;
    }
    /*
     * modifier which gives possibility to call payFiat function
     */
    modifier onlyServiceAgent(){
        require(msg.sender == serviceAgent);
        _;
    }

    /*
    *
    *modifier which gives possibility to purchase
    *
    */
    modifier onlyWhiteList(address _address){
        require(whitelist[_address] == true);
        _;
    }
    /*
     * Enum which defines stages of ICO
    */

    enum Stage {
        Private,
        Discount40,
        Discount20,
        NoDiscount
    }

    //current stage
    Stage public  currentStage;

    //pools of token for each stage
    mapping(uint => uint256) public tokenPools;

    //number of tokens per 1 ether for each stage
    mapping(uint => uint256) public stageRates;

    /*
    * deposit is amount in wei , which was sent to the contract
    * @ address - address of depositor
    * @ uint256 - amount
    */
    mapping(address => uint256) public deposits;

    /* 
    * constructor of contract 
    *  @ _service- address which has rights to call payFiat
    */
    function LuckchemyCrowdsale(address _service) public {
        require(START_TIME_SALE >= now);
        require(START_TIME_SALE > END_TIME_PRESALE);
        require(END_TIME_SALE > START_TIME_SALE);

        require(_service != 0x0);

        owner = msg.sender;
        serviceAgent = _service;
        token = new LuckchemyToken();
        totalSupply = token.CROWDSALE_SUPPLY();

        currentStage = Stage.Private;

        tokenPools[uint(Stage.Private)] = 70000000 * (10 ** (uint256(token.decimals())));
        tokenPools[uint(Stage.Discount40)] = 105000000 * (10 ** (uint256(token.decimals())));
        tokenPools[uint(Stage.Discount20)] = 175000000 * (10 ** (uint256(token.decimals())));
        tokenPools[uint(Stage.NoDiscount)] = 350000000 * (10 ** (uint256(token.decimals())));

        stageRates[uint(Stage.Private)] = RATE_PRIVATE_PRESALE * (10 ** (uint256(token.decimals())));
        stageRates[uint(Stage.Discount40)] = RATE_STAGE_ONE * (10 ** (uint256(token.decimals())));
        stageRates[uint(Stage.Discount20)] = RATE_STAGE_TWO * (10 ** (uint256(token.decimals())));
        stageRates[uint(Stage.NoDiscount)] = RATE_STAGE_THREE * (10 ** (uint256(token.decimals())));

    }

    /*
     * function to get amount ,which invested by depositor
     * @depositor - address ,which bought tokens
    */
    function depositOf(address depositor) public constant returns (uint256) {
        return deposits[depositor];
    }
    /*
     * fallback function can be used to buy  tokens
     */
    function() public payable {
        payETH(msg.sender);
    }


    /*
    * function for tracking ethereum purchases
    * @beneficiary - address ,which received tokens
    */
    function payETH(address beneficiary) public onlyWhiteList(beneficiary) payable {

        require(msg.value >= 0.1 ether);
        require(beneficiary != 0x0);
        require(validPurchase());
        if (isPrivateSale()) {
            processPrivatePurchase(msg.value, beneficiary);
        } else {
            processPublicPurchase(msg.value, beneficiary);
        }


    }

    /*
         * function for processing purchase in private sale
         * @weiAmount - amount of wei , which send to the contract
         * @beneficiary - address for receiving tokens
         */
    function processPrivatePurchase(uint256 weiAmount, address beneficiary) private {

        uint stage = uint(Stage.Private);

        require(tokenPools[stage] > 0);

        //calculate number tokens
        uint tokensToBuy = (weiAmount.mul(stageRates[stage])).div(1 ether);
        if (tokensToBuy <= tokenPools[stage]) {
            //pool has enough tokens
            tokenPools[stage] = tokenPools[stage].sub(tokensToBuy);
            tokensSold = tokensSold.add(tokensToBuy);
            deposits[beneficiary] = deposits[beneficiary].add(weiAmount);

            token.transfer(beneficiary, tokensToBuy);
            TokenETHPurchase(msg.sender, beneficiary, weiAmount, tokensToBuy);

        } else {
            //pool doesn't have enough tokens
            uint leftTokens = tokensToBuy.sub(tokenPools[stage]);
            //left wei
            uint leftWei = leftTokens.mul(1 ether).div(stageRates[stage]);
            uint usedWei = weiAmount.sub(leftWei);
            tokensSold = tokensSold.add(tokenPools[stage]);
            tokenPools[stage] = 0;
            deposits[beneficiary] = deposits[beneficiary].add(usedWei);
            //change stage to Public Sale
            currentStage = Stage.Discount40;

            // tokensToBuy - leftTokens == tokens in pool
            token.transfer(beneficiary, tokensToBuy.sub(leftTokens));
            TokenETHPurchase(msg.sender, beneficiary, usedWei, tokensToBuy.sub(leftTokens));
            //return left wei to beneficiary and change stage
            beneficiary.transfer(leftWei);
        }
    }
    /*
    * function for processing purchase in public sale
    * @weiAmount - amount of wei , which send to the contract
    * @beneficiary - address for receiving tokens
    */
    function processPublicPurchase(uint256 weiAmount, address beneficiary) private {

        if (currentStage == Stage.Private) {
            currentStage = Stage.Discount40;
            tokenPools[uint(Stage.Discount40)] = tokenPools[uint(Stage.Discount40)].add(tokenPools[uint(Stage.Private)]);
            tokenPools[uint(Stage.Private)] = 0;
        }

        for (uint stage = uint(currentStage); stage <= 3; stage++) {

            //calculate number tokens
            uint tokensToBuy = (weiAmount.mul(stageRates[stage])).div(1 ether);

            if (tokensToBuy <= tokenPools[stage]) {
                //pool has enough tokens
                tokenPools[stage] = tokenPools[stage].sub(tokensToBuy);
                tokensSold = tokensSold.add(tokensToBuy);
                deposits[beneficiary] = deposits[beneficiary].add(weiAmount);

                token.transfer(beneficiary, tokensToBuy);
                TokenETHPurchase(msg.sender, beneficiary, weiAmount, tokensToBuy);

                break;
            } else {
                //pool doesn't have enough tokens
                uint leftTokens = tokensToBuy.sub(tokenPools[stage]);

                //calculate left wei for next state
                uint leftWei = leftTokens.mul(1 ether).div(stageRates[stage]);

                //calculate used wei for current stage
                uint usedWei = weiAmount.sub(leftWei);

                tokensSold = tokensSold.add(tokenPools[stage]);
                tokenPools[stage] = 0;
                deposits[beneficiary] = deposits[beneficiary].add(usedWei);

                // tokensToBuy - leftTokens == tokens in pool
                token.transfer(beneficiary, tokensToBuy.sub(leftTokens));
                TokenETHPurchase(msg.sender, beneficiary, usedWei, tokensToBuy.sub(leftTokens));
                if (stage == 3) {
                    //return unused wei when all tokens sold
                    beneficiary.transfer(leftWei);
                    break;
                } else {
                    weiAmount = leftWei;
                    //change current stage
                    currentStage = Stage(stage + 1);
                }
            }
        }
    }
    /*
     * function for change btc agent
     * can be called only by owner of the contract
     * @_newServiceAgent - new serviceAgent address
     */
    function setServiceAgent(address _newServiceAgent) public onlyOwner {
        serviceAgent = _newServiceAgent;
    }
    /*
     * function for tracking bitcoin purchases received by bitcoin wallet
     * each transaction and amount of tokens according to rate can be validated on public bitcoin wallet
     * public key - #
     * @beneficiary - address, which received tokens
     * @amount - amount tokens
     * @amount - number of the stage (80% 40% 20% 0% discount)
     * can be called only by serviceAgent address
     */
    function payFiat(address beneficiary, uint256 amount, uint256 stage) public onlyServiceAgent onlyWhiteList(beneficiary) {

        require(beneficiary != 0x0);
        require(validPurchase());
        require(tokenPools[stage] >= amount);
        require(stage == uint256(currentStage));

        tokenPools[stage] = tokenPools[stage].sub(amount);
        tokensSold = tokensSold.add(amount);

        //calculate fiat amount in wei
        uint fiatWei = amount.mul(1 ether).div(stageRates[stage]);
        fiatBalance = fiatBalance.add(fiatWei);

        token.transfer(beneficiary, amount);
        TokenFiatPurchase(msg.sender, beneficiary, amount);
    }


    /*
     * function for  checking if crowdsale is finished
     */
    function hasEnded() public constant returns (bool) {
        return now > END_TIME_SALE || tokensSold >= totalSupply;
    }

    /*
     * function for  checking if hardCapReached
     */
    function hardCapReached() public constant returns (bool) {
        return tokensSold >= totalSupply;
    }
    /*
     * function for  checking if crowdsale goal is reached
     */
    function goalReached() public constant returns (bool) {
        return fiatBalance.add(this.balance) >= softCap;
    }

    function isPrivateSale() public constant returns (bool) {
        return now >= START_TIME_PRESALE && now <= END_TIME_PRESALE;
    }
    /*
     * function that call after crowdsale is ended
     *          releaseTokenTransfer - enable token transfer between users.
     *          burn tokens which are left on crowsale contract balance
     *          transfer balance of contract to wallets accoridng to shares.
     */

    function forwardFunds() public onlyOwner {
        require(hasEnded());
        require(goalReached());

        token.releaseTokenTransfer();
        token.burn(token.balanceOf(this));


        //transfer token ownership to this owner of crowdsale
        token.transferOwnership(msg.sender);

        //transfer funds here
        uint totalBalance = this.balance;
        LOTTERY_FUND_ADDRESS.transfer((totalBalance.mul(LOTTERY_FUND_SHARE)).div(100));
        MARKETING_ADDRESS.transfer((totalBalance.mul(MARKETING_SHARE)).div(100));
        SUPPORT_ADDRESS.transfer((totalBalance.mul(SUPPORT_SHARE)).div(100));
        DEVELOPMENT_ADDRESS.transfer((totalBalance.mul(DEVELOPMENT_SHARE)).div(100));
        PARTNERS_ADDRESS.transfer((totalBalance.mul(PARTNERS_SHARE)).div(100));


    }
    /*
     * function that call after crowdsale is ended
     *          conditions : ico ended and goal isn't reached. amount of depositor > 0.
     *
     *          refund eth deposit (fiat refunds will be done manually)
     */
    function refund() public {
        require(hasEnded());
        require(!goalReached() || ((now > END_TIME_SALE + 7 days) && !token.released()));
        uint256 amount = deposits[msg.sender];
        require(amount > 0);
        deposits[msg.sender] = 0;
        msg.sender.transfer(amount);

    }

    /*
        internal functions
    */

    /*
     *  function for checking period of investment and investment amount restriction for ETH purchases
     */
    function validPurchase() internal constant returns (bool) {
        bool withinPeriod = (now >= START_TIME_PRESALE && now <= END_TIME_PRESALE) || (now >= START_TIME_SALE && now <= END_TIME_SALE);
        return withinPeriod && !hardCapReached();
    }
    /*
     * function for adding address to whitelist
     * @_whitelistAddress - address to add
     */
    function addToWhiteList(address _whitelistAddress) public onlyServiceAgent {
        whitelist[_whitelistAddress] = true;
    }

    /*
     * function for removing address from whitelist
     * @_whitelistAddress - address to remove
     */
    function removeWhiteList(address _whitelistAddress) public onlyServiceAgent {
        delete whitelist[_whitelistAddress];
    }


}