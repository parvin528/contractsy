pragma solidity 0.8.13;

interface IVoter {
    event GaugeCreated(
        address indexed gauge,
        address creator,
        address feesVotingReward,
        address indexed bribeVotingReward,
        address indexed pool
    );
    event GaugeKilled(address indexed gauge);
    event GaugeRevived(address indexed gauge);
    event Voted(address indexed voter, uint256 tokenId, uint256 weight);
    event Abstained(uint256 tokenId, uint256 weight);
    event Deposit(address indexed lp, address indexed gauge, uint256 amount);
    event Withdraw(address indexed lp, address indexed gauge, uint256 amount);
    event NotifyReward(address indexed sender, address indexed reward, uint256 amount);
    event DistributeReward(address indexed sender, address indexed gauge, uint256 amount);
    event WhitelistToken(address indexed whitelister, address indexed token);
    event WhitelistNFT(address indexed whitelister, uint256 indexed tokenId);

    function gauges(address pool) external view returns (address);

    function ve() external view returns (address);

    function governor() external view returns (address);

    function epochGovernor() external view returns (address);

    function emergencyCouncil() external view returns (address);

    function isWhitelistedToken(address token) external view returns (bool);

    function isAlive(address _gauge) external view returns (bool);

    function usedWeights(uint256 _tokenId) external view returns (uint256);

    function length() external view returns (uint256);

    /// @notice Called by Minter to distribute weekly emissions rewards for disbursement amongst gauges.
    /// @dev Assumes totalWeight != 0 (Will never be zero as long as users are voting).
    ///      Throws if not called by minter.
    /// @param _amount Amount of rewards to distribute.
    function notifyRewardAmount(uint256 _amount) external;

    /// @dev Distribute emissions to gauge of single pool.
    /// @param _gauge Gauge to distribute emissions to.
    function distribute(address _gauge) external;

    /// @dev Utility to distribute to gauges of pools in range _start to _finish.
    /// @param _start   Starting index of gauges to distribute to.
    /// @param _finish  Ending index of gauges to distribute to.
    function distribute(uint256 _start, uint256 _finish) external;

    /// @dev Utility to distribute to gauges of pools in array.
    /// @param _gauges Array of gauges to distribute to.
    function distribute(address[] memory _gauges) external;

    /// @notice Called by users to update voting balances in voting rewards contracts.
    /// @param _tokenId Id of veNFT whose balance you wish to update.
    function poke(uint256 _tokenId) external;

    /// @notice Called by users to vote for pools. Votes distributed proportionally based on weights.
    ///         Can only vote once per epoch.
    /// @dev Weights are distributed proportional to the sum of the weights in the array.
    ///      Throws if length of _poolVote and _weights do not match.
    /// @param _tokenId     Id of veNFT you are voting with.
    /// @param _poolVote    Array of pools you are voting for.
    /// @param _weights     Weights of pools.
    function vote(
        uint256 _tokenId,
        address[] calldata _poolVote,
        uint256[] calldata _weights
    ) external;

    /// @notice Called by users to reset voting state. Required if you wish to make changes to
    ///         veNFT state (e.g. merge, split, deposit into managed etc).
    ///         Can vote again after reset as long as you did not reset in the same week that you voted.
    /// @param _tokenId Id of veNFT you are reseting.
    function reset(uint256 _tokenId) external;

    /// @notice Claim emissions from gauges.
    /// @param _gauges Array of gauges to collect emissions from.
    function claimRewards(address[] memory _gauges) external;

    /// @notice Claim bribes for a given NFT.
    /// @dev Utility to help batch bribe claims.
    /// @param _bribes  Array of BribeVotingReward contracts to collect from.
    /// @param _tokens  Array of tokens that are used as bribes.
    /// @param _tokenId Id of veNFT that you wish to claim bribes for.
    function claimBribes(
        address[] memory _bribes,
        address[][] memory _tokens,
        uint256 _tokenId
    ) external;

    /// @notice Claim fees for a given NFT.
    /// @dev Utility to help batch fee claims.
    /// @param _fees    Array of FeesVotingReward contracts to collect from.
    /// @param _tokens  Array of tokens that are used as fees.
    /// @param _tokenId Id of veNFT that you wish to claim fees for.
    function claimFees(
        address[] memory _fees,
        address[][] memory _tokens,
        uint256 _tokenId
    ) external;

    /// @notice Set new governor.
    /// @dev Throws if not called by governor.
    /// @param _governor .
    function setGovernor(address _governor) external;

    /// @notice Set new epoch based governor.
    /// @dev Throws if not called by governor.
    /// @param _epochGovernor .
    function setEpochGovernor(address _epochGovernor) external;

    /// @notice Set new emergency council.
    /// @dev Throws if not called by emergency council.
    /// @param _emergencyCouncil .
    function setEmergencyCouncil(address _emergencyCouncil) external;

    /// @notice Whitelist token for use in bribes.
    /// @dev Throws if not called by governor.
    /// @param _token .
    function whitelistToken(address _token) external;

    /// @notice Whitelist token id for voting in last hour prior to epoch flip.
    /// @dev Throws if not called by governor.
    ///      Throws if already whitelisted.
    /// @param _tokenId .
    function whitelistNFT(uint256 _tokenId) external;

    /// @notice Create a new gauge (unpermissioned).
    /// @dev Governor can create a new gauge for a pair with any address.
    /// @param _pairFactory .
    /// @param _votingRewardsFactory .
    /// @param _gaugeFactory .
    /// @param _pool .
    function createGauge(
        address _pairFactory,
        address _votingRewardsFactory,
        address _gaugeFactory,
        address _pool
    ) external returns (address);

    /// @notice Kills a gauge. The gauge will not receive any new emissions and cannot be deposited into.
    ///         Can still withdraw from gauge.
    /// @dev Throws if not called by emergency council.
    ///      Throws if gauge already killed.
    /// @param _gauge .
    function killGauge(address _gauge) external;

    /// @notice Revives a killed gauge. Gauge will can receive emissions and deposits again.
    /// @dev Throws if not called by emergency council.
    ///      Throws if gauge is not killed.
    /// @param _gauge .
    function reviveGauge(address _gauge) external;

    /// @dev Update claims to emissions for an array of gauges.
    /// @param _gauges Array of gauges to update emissions for.
    function updateFor(address[] memory _gauges) external;

    /// @dev Update claims to emissions for gauges based on their pool id as stored in Voter.
    /// @param _start   Starting index of pools.
    /// @param _end     Ending index of pools.
    function updateFor(uint256 _start, uint256 _end) external;

    /// @dev Update claims to emissions for single gauge
    /// @param _gauge .
    function updateFor(address _gauge) external;

    /// @dev Claim fees from an array of gauges. Skips gauges not attached to pools.
    /// @param _gauges Array of gauges to claim from.
    function distributeFees(address[] memory _gauges) external;
}