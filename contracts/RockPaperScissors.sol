pragma solidity ^0.7.3;

contract RockPaperScissors {

    mapping(uint => GameData) data;

    uint256 rps_gameID = 0;

    uint MAX_INTERVAL = 15 minutes;
    uint MIN_DEPOSIT  = 10; //dai

    enum Mode {Challenged,Playing,DonePlaying}

    mapping(uint => address) won;
    mapping(uint => bool) isActive;
    uint[] gamesPlayed;

    mapping(address => uint) payOutAmt;
    //mapping(address => uint) betDeposit;
    
    struct GameData {
        address[2] players;
        Mode mode;
        //bool oppTurn;
        bytes32 player0_commit;
        bytes32 player1_commit;        
        Option[2] playersChoice;
        uint betAmt;
        uint initTime;
        uint move1_time;
        uint reveal1_time;
        //address winner;
        // uint gameEndTime;     // expiration date of commit period for game, 10mins
        // uint revealEndTime;   //
        //mapping(address => bool) hasRevealed;   // indicates whether an address revealed a vote for this poll
        //mapping(address => bool) hasCommitted;
        // mapping(address => uint) voteOptions;

    }
    // struct Commits {
    //     bytes player1_commit;
    //     bytes player2_commit;
    // }

    enum Option {none, Rock, Paper, Scissors}
    //enum State {game, commit, reveal}

    //5mins to accept challenge
    // if time is > 5mins the msg.sender can clam their deposit and automatically deletes the game
    // 

    // constructor(address token){

    // }

    function initRPS(address player0, address player1, uint bet) internal payable returns(uint){
        uint id = rps_gameID++; 
        data[id] = GameData({
            players: [player0, player1],
            mode: Mode.Challenged,
            player0_commit: "",
            player1_commit: "",
            playersChoice: [Mode.none, Mode.none],
            initTime: block.timestamp,
            move1_time: 0,
            reveal1_time: 0,
            betAmt: bet
            //winner: address(0)
            //oppTurn: true
        });
        gamesPlayed.push(id);
        isActive[id] = true;
        return id;
    }
    function privateMatch(address _opponent, uint bet) public {
        //uint xtraCash = msg.value;
        if(payOutAmt[msg.sender] < bet) dai.safeTransferFrom(msg.sender, address(this), (bet - payOutAmt[msg.sender])) ;
        require(bet <= payOutAmt[msg.sender]);
        payOutAmt[msg.sender] -= bet;
        //betDeposit[msg.sender] += bet; 
        initRPS(msg.sender, _opponent, bet);
    }
    function publicMatch() public {
        uint bet = MIN_DEPOSIT;
        if(payOutAmt[msg.sender] < bet) dai.safeTransferFrom(msg.sender, address(this), (bet - payOutAmt[msg.sender])) ;
        require(bet <= payOutAmt[msg.sender]);
        payOutAmt[msg.sender] -= bet;
        //betDeposit[msg.sender] += bet; 
        initRPS(msg.sender, address(0), bet);
    }
    function acceptRPS_Challenge(uint rps_id) public payable {
        GameData storage d = data[rps_id];

        require(msg.sender != d.players[0], "Can't Play against self");
        require(d.mode == Mode.Challenged);

        uint bet = d.betAmt;
        if(payOutAmt[msg.sender] < bet) dai.safeTransferFrom(msg.sender, address(this), (bet - payOutAmt[msg.sender])) ;
        require(bet <= payOutAmt[msg.sender]);
        payOutAmt[msg.sender] -= bet;
        //betDeposit[msg.sender] += bet; 
        d.betAmt += bet;

        if(d.players[1] == address(0)) d.players[1] = msg.sender;
        d.mode = Mode.Playing;
    }

    function getPlayerIndex(uint id, address addr) public view returns(uint){
        for(uint i = 0; i < data[id].length; i++){
            if (data[id].players[i] == addr) return i;
        }

    }
    function getOtherPlayerIndex(uint id, address addr) public view{
        getPlayerIndex(id,addr) == 0 ? 1 : 0;
    }

    function play(uint id, bytes32 calldata _rpsCommitHash) public onlyPlayers(id){
        require(_rpsCommitHash != "", "Empty Data");
        GameData storage d = data[id];
        require(d.mode == Mode.Playing);
        
        //require(msg.sender == player0 || msg.sender == player1);
        require(!hasPlayed(id, msg.sender));


        if(msg.sender == d.players[0]){
            d.player0_commit = _rpsCommitHash; 
            //d.hasCommitted[player0] = true;
        }else{ 
            d.player1_commit = _rpsCommitHash;
            //d.hasCommitted[player1] =true;
        }

        address otherPlayer = data[id].players[getOtherPlayerIndex(id, msg.sender)];
        if(!hasPlayed(id, otherPlayer)) d.move1_time = block.timestamp;
        if(hasPlayed(id, otherPlayer)) d.mode = Mode.DonePlaying;
        
    }

    function hasPlayed(uint id, address addr) public view returns(bool){
        data[id].players[0] == addr && data[id].player0_commit == "" ? false
        : data[id].players[0] == addr && data[id].player0_commit != "" ? true
        : data[id].players[1] == addr && data[id].player1_commit == "" ? false
        : true;
    }

    function _allowReplay(uint id) internal {
        GameData storage d = data[id];
        require(d.mode == Mode.DonePlaying);
        d.mode = Mode.Playing;
        d.player2_commit = "";
        d.player1_commit = "";
        d.playersChoice = [Mode.none, Mode.none];
        d.move1_time = 0;
        d.reveal1_time = 0;

    }

    function getCommit(uint id) public view onlyPlayers(id) returns(bytes32){
        // if(msg.sender == data[id].players[0]){
        //     return data[id].player0_commit;
        // } else { 
        //     return data[id].player1_commit;
        // } 
        msg.sender == data[id].players[0] ? data[id].player0_commit : data[id].player1_commit;
    }

    function reveal(uint rps_id, Option _option, uint _salt) public onlyPlayers(rps_id){
        require(data[rps_id].mode == Mode.DonePlaying);
        require(keccak256(abi.encodePacked(_option, _salt)) == getCommit(rps_id), "hash does not match");
        require(_option != Mode.none);
        if(msg.sender == data[rps_id].players[0]){ 
            data[rps_id].playersChoice[0] = _option;
        }else {
            data[rps_id].playersChoice[1] = _option;
        }

        // first reveal time is set by any player who successfully calls this function first
        if (data[id].reveal1_time == 0) data[id].reveal1_time = block.timestamp;
    }


    function _gameLogic(uint rps_id) internal {
    
        GameData memory d = data[rps_id];
        (address player0, address player1) = (d.players[0], d.players[1]);

         d.playersChoice[0] == d.playersChoice[1] ? _allowReplay()
         : d.playersChoice[0] == Option[1] && d.playersChoice[1] != Option[1] ? _win(rps_id, player1)
         : d.playersChoice[0] != Option[1] && d.playersChoice[1] == Option[1] ? _win(rps_id, player0)
         : d.playersChoice[0] == Option[2] && d.playersChoice[1] == Option[3] ? _win(rps_id, player1)
         : d.playersChoice[0] == Option[2] && d.playersChoice[1] == Option[4] ? _win(rps_id, player0)
         : d.playersChoice[0] == Option[3] && d.playersChoice[1] == Option[2] ? _win(rps_id, player0)
         : d.playersChoice[0] == Option[3] && d.playersChoice[1] == Option[4] ? _win(rps_id, player1)
         : d.playersChoice[0] == Option[4] && d.playersChoice[1] == Option[3] ? _win(rps_id, player0)
         : d.playersChoice[0] == Option[4] && d.playersChoice[1] == Option[2] ? _win(rps_id, player1)
         : revert("invalid logic");

    }

    function declareWinner(uint id) public {
        GameData memory d = data[rps_id];
        (address player0, address player1) = (d.players[0], d.players[1]);
        require(hasRevealed(id, player0) && hasRevealed(id, player1));
        _gameLogic(id);
    }

    function hasRevealed(uint id, address addr) public view returns(bool){
        data[id].players[0] == addr && data[id].playersChoice[0] != Option[1] ? true
        : data[id].players[0] == addr && data[id].playersChoice[0] == Option[1] ? false
        : data[id].players[1] == addr && data[id].playersChoice[1] != Option[1] ? true
        : false;
    }

    function _win(uint id, address player) internal {
        uint amt = data[id].betAmt;

        //betDeposit[player] -= amt;
        payOutAmt[player] += amt;

        won[id] = player;
        isActive[id] = false;
        
        delete data[id];
    }

    function getWinner(uint rps_id) public view returns(address){
        return won[rps_id];
    }

    function claim() public {
        uint amt = payOutAmt[msg.sender];
        dai.safeTransferFrom(address(this), msg.sender, amt);
        payOutAmt[msg.sender] = 0;
    }

    modifier onlyPlayers(uint id) {
        require(msg.sender == data[id].players[0] || msg.sender == data[id].players[0]);
        _;
    }
    //mod

    function matchnroll() public {
        uint[] memory g;
        for(uint i = 0; i <= gamesPlayed.length; i++ ){
            uint j = gamesPlayed[i];
            if(isActive(j) && data[j].players[1] == address(0)){
                g.push(j);
            }
        }
        (g.length >= 1) ? acceptRPS_Challenge(g[0]) 
        : publicMatch();
        

    }

    function settleDispute(uint id) public {
        GameData memory d = data[id];
        (address player0 , address player1) = (d.players[0], d.players[1]);        
        if(d.mode == Mode.Challenged && d.initTime + MAX_INTERVAL < block.timestamp){
            _win(id, player0);
        } else if( d.mode == Mode.Playing && d.move1_time + MAX_INTERVAL < block.timestamp){
            if(hasPlayed(id, player0) && !hasPlayed(id, player1)){
                _win(id, player0);
            } else if(hasPlayed(id, player1) && !hasPlayed(id, player0)){
                _win(id, player1);
            } else {
                revert("No dispute");
            }
        } else if( d.mode == Mode.DonePlaying && d.reveal1_time + MAX_INTERVAL < block.timestamp){
            _gameLogic(id);
        } else {
            revert("No dispute");
        }
    }

}
