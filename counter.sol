// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOpenOracleVRFFeed {
    function requestRandomness() external returns (uint256 requestId);
    function fulfillRandomness(uint256 requestId, uint256 randomness) external;
}

contract EpochRaffle {
    struct Epoch {
        uint256 startTime;
        uint256 endTime;
        address payable[] participants;
        uint256 totalPrize;
        bool finished;
    }

    IOpenOracleVRFFeed public vrfContract;
    uint256 public currentEpoch;
    uint256 public epochDuration;
    mapping(uint256 => Epoch) public epochs;
    mapping(uint256 => uint256) public lastRequestIds;

    event EpochStarted(uint256 indexed epochId, uint256 startTime, uint256 endTime);
    event Deposit(uint256 indexed epochId, address participant, uint256 amount);
    event WinnerSelected(uint256 indexed epochId, address winner, uint256 amount);

    constructor(uint256 _epochDuration) {
        vrfContract = IOpenOracleVRFFeed(0x2ea329336246e89BFF5bB87E6dCc74EBe9d2b039);
        epochDuration = _epochDuration;
        startNewEpoch();
    }

    function startNewEpoch() internal {
        currentEpoch++;
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + epochDuration;
        epochs[currentEpoch] = Epoch(startTime, endTime, new address payable[](0), 0, false);
        emit EpochStarted(currentEpoch, startTime, endTime);
    }

    function deposit() public payable {
        require(msg.value > 0, "Must send some ETH to enter");
        require(block.timestamp < epochs[currentEpoch].endTime, "Epoch has ended");

        epochs[currentEpoch].participants.push(payable(msg.sender));
        epochs[currentEpoch].totalPrize += msg.value;

        emit Deposit(currentEpoch, msg.sender, msg.value);
    }

    function pickWinner() public {
        require(block.timestamp >= epochs[currentEpoch].endTime, "Epoch not yet ended");
        require(!epochs[currentEpoch].finished, "Winner already picked for this epoch");
        require(epochs[currentEpoch].participants.length > 0, "No participants in this epoch");

        lastRequestIds[currentEpoch] = vrfContract.requestRandomness();
        epochs[currentEpoch].finished = true;
    }

    function fulfillRandomness(uint256 requestId, uint256 randomness) public {
        require(msg.sender == address(vrfContract), "Only VRF can fulfill");
        
        uint256 epochId = currentEpoch;
        while (epochId > 0 && lastRequestIds[epochId] != requestId) {
            epochId--;
        }
        require(epochId > 0, "Request ID not found");

        Epoch storage epoch = epochs[epochId];
        uint256 index = randomness % epoch.participants.length;
        address payable winner = epoch.participants[index];

        uint256 winnerPrize = (epoch.totalPrize * 60) / 100;
        uint256 burnAmount = epoch.totalPrize - winnerPrize;

        winner.transfer(winnerPrize);
        payable(address(0)).transfer(burnAmount); // Burn the rest

        emit WinnerSelected(epochId, winner, winnerPrize);

        if (epochId == currentEpoch) {
            startNewEpoch();
        }
    }

    function getCurrentEpochInfo() public view returns (uint256 startTime, uint256 endTime, uint256 totalPrize, uint256 participantCount) {
        Epoch storage epoch = epochs[currentEpoch];
        return (epoch.startTime, epoch.endTime, epoch.totalPrize, epoch.participants.length);
    }
}
