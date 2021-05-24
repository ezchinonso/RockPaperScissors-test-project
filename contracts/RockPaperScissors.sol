// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RockPaperScissors {

    // mapping of match ID to GameData struct
    mapping(uint => GameData) data;

    mapping(uint => mapping(address => bool)) hasPlayed;
    mapping(uint => mapping(address => bool)) hasRevealed;

    uint256 rps_gameID = 0;

    uint constant MAX_INTERVAL = 15 minutes;
    uint constant MIN_DEPOSIT  = 10; //* 10 ** 18; //dai

    IERC20 public dai;



    // mapping of match ID to match winner 
    mapping(uint => address) won;
    // mapping of match ID to bool
    mapping(uint => bool) isActive;
    // all rps matches played
    uint[] gamesPlayed;

    uint[] cache;

    mapping(address => uint) payOutAmt;
    //mapping(address => uint) betDeposit;
    
    struct GameData {
        // [player0, player1]
        address[2] players;
        Mode mode;
        // player0 commitHash
        bytes32 player0_commit;
        // player1 commitHash
        bytes32 player1_commit; 
        // [Player0 Option, player1 Option]       
        Option[2] playersChoice;
        // bet amount
        uint betAmt;
        // rps initialization timestamp
        uint initTime;
        // timestamp for first move
        uint move1_time;
        // timestamp for first reveal
        uint reveal1_time;
    }

    /******************* ENUMS ************************/

    enum Option {none, Rock, Paper, Scissors}
    enum Mode {Challenged,Playing,DonePlaying}

    /******************* EVENTS ************************/

    event RPS_Initialized(uint id, address player0, address player1);
    event Played(uint id, address player, bytes32 commit);
    event Revealed(uint id, address player, Option option);
    event Replay(uint id);
    event ChallengeAccepted(uint id, address player);
    event Winner(uint id, uint amt, address player);
    event Claimed(uint amt, address player);


    /*************************** INTERNAL FUNCTIONS *********************/

    // Initializes RPS match
    function initRPS(address player0, address player1, uint bet) internal returns(uint){
        rps_gameID++;
        uint id = rps_gameID; 
        data[id] = GameData({
            players: [player0, player1],
            mode: Mode.Challenged,
            player0_commit: "",
            player1_commit: "",
            playersChoice: [Option.none, Option.none],
            initTime: block.timestamp,
            move1_time: 0,
            reveal1_time: 0,
            betAmt: bet
        });
        gamesPlayed.push(id);
        isActive[id] = true;
        emit RPS_Initialized(id, player0, player1);
        return id;
    }
    // allows players to replay a match
    function _allowReplay(uint id) internal {
        GameData storage d = data[id];
        require(d.mode == Mode.DonePlaying);
        d.mode = Mode.Playing;
        d.player0_commit = "";
        d.player1_commit = "";
        d.playersChoice = [Option.none, Option.none];
        d.move1_time = 0;
        d.reveal1_time = 0;

        emit Replay(id);
    }

    // _gameLogic decides RPS match winner 
    function _gameLogic(uint rps_id) internal {
        GameData memory d = data[rps_id];
        (address player0, address player1) = (data[rps_id].players[0], data[rps_id].players[1]);

         uint(d.playersChoice[0]) == uint(d.playersChoice[1]) ? _allowReplay(rps_id) 
         : uint(d.playersChoice[0]) == 0 && uint(d.playersChoice[1]) != 0 ? _win(rps_id, player1) 
         : uint(d.playersChoice[0]) != 0 && uint(d.playersChoice[1]) == 0 ? _win(rps_id, player0) 
         : uint(d.playersChoice[0]) == 1 && uint(d.playersChoice[1]) == 2 ? _win(rps_id, player1) 
         : uint(d.playersChoice[0]) == 1 && uint(d.playersChoice[1]) == 3 ? _win(rps_id, player0) 
         : uint(d.playersChoice[0]) == 2 && uint(d.playersChoice[1]) == 1 ? _win(rps_id, player0) 
         : uint(d.playersChoice[0]) == 2 && uint(d.playersChoice[1]) == 3 ? _win(rps_id, player1) 
         : uint(d.playersChoice[0]) == 3 && uint(d.playersChoice[1]) == 2 ? _win(rps_id, player0) 
         : uint(d.playersChoice[0]) == 3 && uint(d.playersChoice[1]) == 1 ? _win(rps_id, player1) 
         : revert("invalid logic");

    }

    // _win func. makes player winner and tranfers match bet amount to player
    // deletes GameData for match
    // emits winner event
    function _win(uint id, address player) internal {
        uint amt = data[id].betAmt;

        payOutAmt[player] += amt;

        won[id] = player;
        isActive[id] = false;
        
        delete data[id];

        emit Winner(id, amt, player);
    }

    // _match() - initializes match with constant bet amount
    function _match() internal {
        uint bet = MIN_DEPOSIT;
        if(payOutAmt[msg.sender] < bet) deposit(bet - payOutAmt[msg.sender]) ;
        require(bet <= payOutAmt[msg.sender]);
        payOutAmt[msg.sender] -= bet;
        //betDeposit[msg.sender] += bet; 
        initRPS(msg.sender, address(0), bet);
    }

    // accept RPS match challenge
    function _acceptRPS_Challenge(uint rps_id) internal {
        GameData storage d = data[rps_id];

        require(msg.sender != d.players[0], "Can't Play against self");
        require(d.mode == Mode.Challenged);

        uint bet = d.betAmt;
        if(payOutAmt[msg.sender] < bet) deposit(bet - payOutAmt[msg.sender]);
        require(bet <= payOutAmt[msg.sender]);
        payOutAmt[msg.sender] -= bet;
        //betDeposit[msg.sender] += bet; 
        d.betAmt += bet;

        if(d.players[1] == address(0)) d.players[1] = msg.sender;
        d.mode = Mode.Playing;

        emit ChallengeAccepted(rps_id, msg.sender);
    }


    /*************************** PUBLIC FUNCTIONS *********************/

    function deposit(uint amt) public {
        dai.approve(address(this), uint(-1));
        dai.transferFrom(msg.sender, address(this), amt);
        payOutAmt[msg.sender] += amt;
    }

    // customMatch allows msg.sender to initialize match and play against a certain player(oppponent) 
    // also allows msg.sender to set custom bet amount
    // 
    function customMatch(address _opponent, uint bet) public {
        if(payOutAmt[msg.sender] < bet) deposit(bet - payOutAmt[msg.sender]) ;
        require(bet <= payOutAmt[msg.sender]);
        payOutAmt[msg.sender] -= bet;
         
        initRPS(msg.sender, _opponent, bet);
    }

    // accept custom match challenge
    function acceptPrivateChallenge(uint rps_id) public {
        require(data[rps_id].players[1] != address(0));
        _acceptRPS_Challenge(rps_id);
    }
    
    // 
    function play(uint id, bytes32 _rpsCommitHash) public onlyPlayers(id){
        GameData storage d = data[id];
        require(d.mode == Mode.Playing, "not in this mode");
        require(_rpsCommitHash != "", "Empty Data");
        
        require(!hasPlayed[id][msg.sender], "has played");


        if(msg.sender == d.players[0]){
            d.player0_commit = _rpsCommitHash; 
            //d.hasCommitted[player0] = true;
        }else{ 
            d.player1_commit = _rpsCommitHash;
            //d.hasCommitted[player1] =true;
        }

        address otherPlayer = data[id].players[getOtherPlayerIndex(id, msg.sender)];

        // if opponent has not played set the first move time to now
        if(!hasPlayed[id][otherPlayer]) d.move1_time = block.timestamp;
        // if opponent has played update mode to done playing
        if(hasPlayed[id][otherPlayer]) d.mode = Mode.DonePlaying;
        
        hasPlayed[id][msg.sender] = true;
        
        emit Played(id, msg.sender, _rpsCommitHash);
    }


    
    // reveals player move from commitHash
    function reveal(uint rps_id, Option _option, uint _salt) public onlyPlayers(rps_id){
        require(data[rps_id].mode == Mode.DonePlaying);
        require(keccak256(abi.encodePacked(_option, _salt)) == getCommit(rps_id), "hash does not match");
        require(_option == Option.Rock || _option == Option.Paper || _option == Option.Scissors);
        if(msg.sender == data[rps_id].players[0]){ 
            data[rps_id].playersChoice[0] = _option;
        }else {
            data[rps_id].playersChoice[1] = _option;
        }

        // first reveal time is set by any player who successfully calls this function first
        if (data[rps_id].reveal1_time == 0) data[rps_id].reveal1_time = block.timestamp;
        hasRevealed[rps_id][msg.sender] = true;

        emit Revealed(rps_id, msg.sender, _option);
    }


    // checks if both player have revealed their options and uses game logic to declare match winner
    function declareWinner(uint id) public {
        GameData memory d = data[id];
        (address player0, address player1) = (d.players[0], d.players[1]);
        require(hasRevealed[id][player0] && hasRevealed[id][player1]);
        _gameLogic(id);
    }

    

    // withdraw deposits and match payouts from this contract
    function claim() public {
        uint amt = payOutAmt[msg.sender];
        require(amt > 0, "Zero Balance");
        dai.transferFrom(address(this), msg.sender, amt);
        payOutAmt[msg.sender] = 0;

        emit Claimed(amt, msg.sender);
    }


    // auto enrolls msg.sender into rps match
    function matchnroll() public{

        for(uint i = 0; i < gamesPlayed.length; i++ ){
            uint j = gamesPlayed[i];
            if(isActive[j] && data[j].players[1] == address(0)){
                cache.push(j);
            }
        }
        // uint c = cache[0];
        (cache.length > 0) ? _acceptRPS_Challenge(cache[0]) : _match();
        delete cache;
    }

    // settleDispute function intervenes if opponent is uncooperative or willing to play
    // - allows player to withdraw their bet if player refuses to accept challenge within MAX_INTERVAL
    // - declares player winnner if opponent refuses to play within MAX_INTERVAL
    // - enforces game logic if match opponent refuses to reveal move within MAX_INTERVAL
    function settleDispute(uint id) public {
        GameData memory d = data[id];
        (address player0 , address player1) = (d.players[0], d.players[1]);        
        if(d.mode == Mode.Challenged && (d.initTime + MAX_INTERVAL) < block.timestamp){
            _win(id, player0);
        } else if( d.mode == Mode.Playing && (d.move1_time + MAX_INTERVAL) < block.timestamp){
             require(d.move1_time != 0, "No move made yet");
            if(hasPlayed[id][player0] && !hasPlayed[id][player1]){
                _win(id, player0);
            } else if(hasPlayed[id][player1] && !hasPlayed[id][player0]){
                _win(id, player1);
            } else { revert("No dispute");}
        } else if( d.mode == Mode.DonePlaying && (d.reveal1_time + MAX_INTERVAL) < block.timestamp){
             require(d.reveal1_time != 0, "No reveal made yet");
            _gameLogic(id);
        } else {
            revert("No dispute");
        }
    }

    
    
    

    /*************************** VIEW FUNCTIONS *********************/

    function getCommit(uint id) public view onlyPlayers(id) returns(bytes32){
        return msg.sender == data[id].players[0] ? data[id].player0_commit : data[id].player1_commit;
    }
    function getGameData(uint id) public view returns(GameData memory){
        return data[id];
    }
    function getWinner(uint rps_id) public view returns(address){
        return won[rps_id];
    }
    // function hasRevealed(uint id, address addr) public view returns(bool){
    //     data[id].players[0] == addr && uint(data[id].playersChoice[0]) != 1 ? true
    //     : data[id].players[0] == addr && uint(data[id].playersChoice[0]) == 1 ? false
    //     : data[id].players[1] == addr && uint(data[id].playersChoice[1]) != 1 ? true
    //     : false;
    // }
    // function hasPlayed(uint id, address addr) public view returns(bool){
    //     data[id].players[0] == addr && data[id].player0_commit == "" ? false
    //     : data[id].players[0] == addr && data[id].player0_commit != "" ? true
    //     : data[id].players[1] == addr && data[id].player1_commit == "" ? false
    //     : true;
    // }
    function getPlayerIndex(uint id, address addr) public view returns(uint){
        //require(msg.sender == data[id].players[0] || msg.sender == data[id].players[1]);
        if (data[id].players[0] == addr){
            return 0;
        }else if(data[id].players[1] == addr){ return 1;
        }else{ revert();}
    }
    function getOtherPlayerIndex(uint id, address addr) public view returns(uint){
        //require(msg.sender == data[id].players[0] || msg.sender == data[id].players[1]);
        return getPlayerIndex(id,addr) == 0 ? 1 : 0;
    }
    function getPlayerBalance(address addr)public view returns(uint){
        return payOutAmt[addr];
    }

    /************************ HELPER FUNCTIONS ********************/

    function generateCommitHash(Option _option, uint salt) public view returns(bytes32){
        return keccak256(abi.encodePacked(_option, salt));
    }

    /*************************** MODIFIERS *********************/

    modifier onlyPlayers(uint id) {
        require(msg.sender == data[id].players[0] || msg.sender == data[id].players[1], "Not a participant");
        _;
    }


    constructor(address token){
        // accepted token instance
        dai = IERC20(token);
    }

}
