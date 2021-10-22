//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

contract CollectorDAO {

  /// @notice Possible states that a proposal may be in
  enum ProposalState {
    Pending,
    Active,
    Canceled,
    Defeated,
    Succeeded,
    Queued,
    Expired,
    Executed
  }

  /// @notice Internal proposal counter
  uint private proposalCount;

  /// @notice Total DAO Membership
  uint public totalMembers;
  
  /// @notice Quorum threshold should comprise 25% of total DAO membership
  uint8 private constant QUORUM_THRESHOLD = 25;

  struct Proposal {
    /// @notice Unique id for looking up a proposal
    uint id;

    /// @notice Creator of the proposal
    address proposer;

    /// @notice The timestamp that the proposal will be available for execution, set once the vote succeeds
    uint eta;

    /// @notice the ordered list of target addresses for calls to be made
    address[] targets;

    /// @notice The ordered list of values (i.e. msg.value) to be passed to the calls to be made
    uint[] values;

    /// @notice The ordered list of function signatures to be called
    string[] signatures;

    /// @notice The ordered list of calldata to be passed to each call
    bytes[] calldatas;

    /// @notice The block at which voting begins: holders must delegate their votes prior to this block
    uint startBlock;

    /// @notice The block at which voting ends: votes must be cast prior to this block
    uint endBlock;

    /// @notice Current number of votes in favor of this proposal
    uint forVotes;

    /// @notice Current number of votes in opposition to this proposal
    uint againstVotes;

    /// @notice Current number of votes in opposition to this proposal
    uint abstainVotes;

    /// @notice Flag marking whether the proposal has been canceled
    bool canceled;

    /// @notice Flag marking whether the proposal has been executed
    bool executed;
  }

  /// @notice Ballot receipt record for a voter
  struct Receipt {
    /// @notice Whether or not a vote has been cast
    bool hasVoted;

    /// @notice Whether or not the voter supports the proposal
    bool support;
  }



  /// @notice 
  mapping (uint => mapping (address => Receipt)) receipts;

  /// @notice Mapping of current DAO Members
  mapping(address => bool) private _members;
  
  /// @notice The official record of all proposals ever proposed
  mapping (uint => Proposal) public proposals;
  


  /// @notice An event emitted when a new member joins the DAO
  event NewMemberAdded(address member);

  /// @notice An event emitted when a new proposal is created
  event ProposalCreated(uint id, address proposer, address[] targets, uint[] values, string[] signatures, bytes[] calldatas, uint startBlock, uint endBlock, string description);

  /// @notice An event emitted when a vote has been cast on a proposal
  event VoteCast(address voter, uint proposalId, bool support);

  /// @notice An event emitted when a proposal has been canceled
  event ProposalCanceled(uint id);

  /// @notice An event emitted when a proposal has been queued in the Timelock
  event ProposalQueued(uint id, uint eta);

  /// @notice An event emitted when a proposal has been executed in the Timelock
  event ProposalExecuted(uint id);

  /// @notice 25% of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed
  function quorumVotes() public view returns (uint) { 
    return (QUORUM_THRESHOLD * totalMembers) / 100;
  }

  /// @notice The delay before voting on a proposal may take place, once proposed
  function votingDelay() public pure returns (uint) { return 1; } // 1 block

  /// @notice The duration of voting on a proposal, in blocks
  function votingPeriod() public pure returns (uint) { return 51840; } // ~9 days in blocks (assuming 15s blocks)

  function join() external payable returns (bool) {
    require(msg.value == 1 ether, "CollectorDAO:: insufficient funds");
    require(_members[msg.sender] == false, "CollectorDAO:: already a member");
    _members[msg.sender] = true;
    totalMembers++;
    emit NewMemberAdded(msg.sender);
    return true;
  }

  function isMember(address _address) external view returns (bool) {
    return _members[_address];
  }

  /**
    * @notice Function used to propose a new proposal. Sender must have delegates above the proposal threshold
    * @param targets Target addresses for proposal calls
    * @param values Eth values for proposal calls
    * @param signatures Function signatures for proposal calls
    * @param calldatas Calldatas for proposal calls
    * @param description String description of the proposal
    * @return Proposal id of new proposal
    */
  function propose(address[] memory targets, uint[] memory values, string[] memory signatures, bytes[] memory calldatas, string memory description) public returns (uint) {
    require(targets.length == values.length && targets.length == signatures.length && targets.length == calldatas.length, "CollectorDAO::propose: proposal function information arity mismatch");
    require(targets.length != 0, "CollectorDAO::propose: must provide actions");

    uint startBlock = block.number + votingDelay();
    uint endBlock = startBlock + votingPeriod();

    proposalCount++;
    Proposal memory newProposal = Proposal({
      id: proposalCount,
      proposer: msg.sender,
      eta: 0,
      targets: targets,
      values: values,
      signatures: signatures,
      calldatas: calldatas,
      startBlock: startBlock,
      endBlock: endBlock,
      forVotes: 0,
      againstVotes: 0,
      abstainVotes: 0,
      canceled: false,
      executed: false
    });

    proposals[newProposal.id] = newProposal;

    emit ProposalCreated(newProposal.id, msg.sender, targets, values, signatures, calldatas, startBlock, endBlock, description);
    return newProposal.id;
  }

  function state(uint proposalId) public view returns (ProposalState) {
    require(proposalCount >= proposalId && proposalId > 0, "CollectorDAO::state: invalid proposal id");
    Proposal storage proposal = proposals[proposalId];
    if (proposal.canceled) {
        return ProposalState.Canceled;
    } else if (block.number <= proposal.startBlock) {
        return ProposalState.Pending;
    } else if (block.number <= proposal.endBlock) {
        return ProposalState.Active;
    } else if (proposal.forVotes <= proposal.againstVotes || proposal.forVotes < quorumVotes()) {
        return ProposalState.Defeated;
    } else if (proposal.eta == 0) {
        return ProposalState.Succeeded;
    } else if (proposal.executed) {
        return ProposalState.Executed;
    } else if (block.timestamp >= proposal.eta) {
        return ProposalState.Expired;
    } else {
        return ProposalState.Queued;
    }
  }

  function castVote(uint proposalId, bool support) external {
    require(_members[msg.sender] == true, "CollectorDAO:: not a member");
    return _castVote(msg.sender, proposalId, support);
  }

  function _castVote(address voter, uint proposalId, bool support) internal {
    require(state(proposalId) == ProposalState.Active, "c::_castVote: voting is closed");
    Proposal storage proposal = proposals[proposalId];
    Receipt storage receipt = receipts[proposalId][voter];
    require(receipt.hasVoted == false, "CollectorDAO::_castVote: voter already voted");
    support ? proposal.forVotes++ : proposal.againstVotes++;
    
    receipt.hasVoted = true;
    receipt.support = support;

    emit VoteCast(voter, proposalId, support);
  }


}
