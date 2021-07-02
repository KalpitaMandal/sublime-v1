// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.0;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "@openzeppelin/contracts/math/SafeMath.sol";

import "./RepaymentStorage.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IRepayment.sol";
import "../interfaces/ISavingsAccount.sol";

import "hardhat/console.sol";

contract Repayments is RepaymentStorage, IRepayment {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address PoolFactory;

    event InterestRepaid(address poolID, uint256 repayAmount); // Made during current period interest repayment
    event MissedRepaymentRepaid(address poolID); // Previous period's interest is repaid fully
    event PartialExtensionRepaymentMade(address poolID); // Previous period's interest is repaid partially

    modifier isPoolInitialized() {
        require(
            repaymentConstants[msg.sender].numberOfTotalRepayments != 0,
            "Pool is not Initiliazed"
        );
        _;
    }

    modifier onlyValidPool {
        require(
            IPoolFactory(PoolFactory).openBorrowPoolRegistry(msg.sender),
            "Repayments::onlyValidPool - Invalid Pool"
        );
        _;
    }

    function initialize(
        address _owner,
        address _poolFactory,
        uint256 _votingPassRatio,
        address _savingsAccount
    ) public initializer {
        // _votingExtensionlength - should enforce conditions with repaymentInterval
        OwnableUpgradeable.__Ownable_init();
        OwnableUpgradeable.transferOwnership(_owner);

        votingPassRatio = _votingPassRatio;
        PoolFactory = _poolFactory;
        savingsAccount = _savingsAccount;
    }

    function initializeRepayment(
        uint256 numberOfTotalRepayments,
        uint256 repaymentInterval,
        uint256 borrowRate,
        uint256 loanStartTime,
        address lentAsset
    ) external override onlyValidPool {
        repaymentConstants[msg.sender].gracePenaltyRate = gracePenaltyRate;
        repaymentConstants[msg.sender].gracePeriodFraction = gracePeriodFraction;
        repaymentConstants[msg.sender]
            .numberOfTotalRepayments = numberOfTotalRepayments;
        repaymentConstants[msg.sender].loanDuration = repaymentInterval.mul(
            numberOfTotalRepayments
        );
        repaymentConstants[msg.sender].repaymentInterval = repaymentInterval;
        repaymentConstants[msg.sender].borrowRate = borrowRate;
        repaymentConstants[msg.sender].loanStartTime = loanStartTime;
        repaymentConstants[msg.sender].repayAsset = lentAsset;
        repaymentConstants[msg.sender].savingsAccount = savingsAccount;
        repaymentVars[msg.sender].nextDuePeriod = loanStartTime.add(repaymentInterval);
    }

    function getInterestDueThisPeriod(address _poolID) 
        public
        view
        returns (uint256)
    {
        uint256 activePrincipal = IPool(_poolID).getTotalSupply();

        uint256 interestPerSecond =
            activePrincipal.mul(repaymentConstants[_poolID].borrowRate).div(
                yearInSeconds
            );

        uint256 interestDueTillPeriodEnd =
            interestPerSecond.mul(
                (repaymentConstants[_poolID].repaymentInterval).sub(
                    repaymentVars[_poolID].repaymentPeriodCovered
                )
            ).div(10**30); // multiplying exponents

        return interestDueTillPeriodEnd;
    }

    /*
    * @notice returns the number of repayment intervals that have been repaid, 
    * if repayment interval = 10 secs, loan duration covered = 55 secs, repayment intervals covered = 5
    * @param _poolID address of the pool
    */

    function getRepaymentIntervalsCovered(address _poolID) 
        public 
        view 
        returns (uint256)
    {
        uint256 activePrincipal = IPool(_poolID).getTotalSupply();

        uint256 interestPerSecond =
            activePrincipal.mul(repaymentConstants[_poolID].borrowRate).div(
                yearInSeconds
            );

        uint256 _repaymentInterval = repaymentConstants[_poolID].repaymentInterval;
        uint256 _loanDurationCovered = repaymentVars[_poolID].loanDurationCovered;

        uint256 _repaymentIntervalsCovered = _loanDurationCovered.mul(10**30).div(_repaymentInterval); // dividing exponents

        return _repaymentIntervalsCovered;
    }

    function getOngoingLoanInterval(address _poolID) 
        external 
        override  
        view 
        returns (uint256)
    {
        uint256 _loanStartTime = repaymentConstants[_poolID].loanStartTime;
        uint256 _currentTime = block.timestamp;
        uint256 _repaymentInterval = repaymentConstants[_poolID].repaymentInterval;
        uint256 _ongoingInterval = ((_currentTime.sub(_loanStartTime)).mul(10**30).div(_repaymentInterval)).add(10**30); // TODO add 10**30 to add 1 - check

        return _ongoingInterval;
    }

    function isGracePenaltyApplicable(address _poolID) 
        public 
        view 
        returns (bool)
    {
        uint256 _loanStartTime = repaymentConstants[_poolID].loanStartTime;
        uint256 _repaymentInterval = repaymentConstants[_poolID].repaymentInterval;
        uint256 _currentTime = block.timestamp;

        uint256 _currentLoanInterval = getOngoingLoanInterval(_poolID);
        uint256 _currentLoanIntervalEndTime = _loanStartTime
                                                .add((_currentLoanInterval.mul(_repaymentInterval).div(10**30))); // multiplying exponents
        uint256 _loanDurationCovered = repaymentVars[_poolID].loanDurationCovered;

        
        if (_currentTime > _currentLoanIntervalEndTime && 
            _loanStartTime.add(_loanDurationCovered) < _currentLoanIntervalEndTime) {
            return true;
        }
        else {
            return false;
        }
    }

    // TODO need to recheck the conditions of defualt
    // TODO case where borrower is defaulting even if loan extension is active

    function didBorrowerDefault(address _poolID) 
        public 
        view  
        returns (bool)
    {
        uint256 _currentTime = block.timestamp;
        bool _isLoanExtensionActive = repaymentVars[_poolID].isLoanExtensionActive;
        uint256 _repaymentInterval = repaymentConstants[_poolID].repaymentInterval;
        uint256 _loanStartTime = repaymentConstants[_poolID].loanStartTime;
        uint256 _gracePeriodFraction = repaymentConstants[_poolID].gracePeriodFraction;

        uint256 _currentLoanInterval = getOngoingLoanInterval(_poolID);
        uint256 _currentLoanIntervalEndTime = _loanStartTime
                                                .add((_currentLoanInterval.mul(_repaymentInterval).div(10**30))); // multiplying exponents
        uint256 _loanDurationCovered = repaymentVars[_poolID].loanDurationCovered;

        if (_currentTime > _currentLoanIntervalEndTime.add(_gracePeriodFraction.mul(_repaymentInterval).div(10**30)) &&
            _loanStartTime.add(_loanDurationCovered) < _currentLoanIntervalEndTime &&
            _isLoanExtensionActive == false) // 1st condition checks current time vs interval end time, 2nd condition checks if interval interest has already been repaid
        {
            return true;
        }

        else {
            return false;
        }

    }




/*
    function calculateRepayAmount(address poolID)
        public
        view
        override
        returns (uint256)
    {
        uint256 activePrincipal = IPool(poolID).getTotalSupply();
        // assuming repaymentInterval is in seconds
        //uint256 currentPeriod = (block.timestamp.sub(repaymentConstants[poolID].loanStartTime)).div(repaymentConstants[poolID].repaymentInterval);

        uint256 interestPerSecond =
            activePrincipal.mul(repaymentConstants[poolID].borrowRate).div(
                yearInSeconds
            );

        // uint256 periodEndTime = (currentPeriod.add(1)).mul(repaymentInterval);

        uint256 interestDueTillPeriodEnd =
            interestPerSecond.mul(
                (repaymentConstants[poolID].repaymentInterval).sub(
                    repaymentVars[poolID].repaymentPeriodCovered
                )
            );
        return interestDueTillPeriodEnd;
    }
*/
    // TODO need to add grace penalty

    function repayAmount(address _poolID, uint256 _amount) public payable isPoolInitialized {
        IPool _pool = IPool(_poolID);

        uint256 _loanStatus = _pool.getLoanStatus();
        require(_loanStatus == 1,
                "Repayments:repayInterest Pool should be active.");

        uint256 _amountRequired = 0;

        // First pay off the overdue
        if(repaymentVars[_poolID].repaymentOverdue != 0) {
            if (_amount >= repaymentVars[_poolID].repaymentOverdue) {
                repaymentVars[_poolID].repaymentOverdue = 0;
                _amount = _amount.sub(repaymentVars[_poolID].repaymentOverdue);
                _amountRequired = _amountRequired.add(repaymentVars[_poolID].repaymentOverdue);
                repaymentVars[_poolID].isLoanExtensionActive = false; // deactivate loan extension flag
            }
            else {
                uint256 _repaymentOverdue = repaymentVars[_poolID].repaymentOverdue;
                repaymentVars[_poolID].repaymentOverdue = _repaymentOverdue.sub(_amount);
                _amount = 0;
                _amountRequired = _amountRequired.add(_amount);
            }
        }

        // Second pay off the interest
        if(_amount != 0) {
            uint256 _activePrincipal = _pool.getTotalSupply();
            uint256 _interestPerSecond = _activePrincipal
                                        .mul(repaymentConstants[_poolID].borrowRate)
                                        .div(yearInSeconds);

            uint256 _loanDurationLeft = repaymentConstants[_poolID].loanDuration
                                        .sub(repaymentVars[_poolID].loanDurationCovered);

            uint256 _interestLeft = _interestPerSecond.mul(_loanDurationLeft).div(10**30); // multiplying exponents

            if (_amount < _interestLeft) {
                uint256 _loanDurationCovered = _amount.mul(10**30).div(_interestPerSecond); // dividing exponents
                repaymentVars[_poolID].loanDurationCovered = repaymentVars[_poolID].loanDurationCovered
                                                        .add(_loanDurationCovered);
                _amount = 0;
                _amountRequired = _amountRequired.add(_amount);
            }
            else {
                repaymentVars[_poolID].loanDurationCovered = repaymentConstants[_poolID].loanDuration; // full interest repaid
                _amount = _amount.sub(_interestLeft);
                _amountRequired = _amountRequired.add(_interestLeft);
            }

            uint256 _nextDuePeriod = (repaymentVars[_poolID].loanDurationCovered.mul(10**30).div(repaymentConstants[_poolID].repaymentInterval)).add(10**30); // dividing exps, adding 1 b/c next due period is one ahead period covered
            repaymentVars[_poolID].nextDuePeriod = _nextDuePeriod;
            _pool.updateNextDuePeriod(_nextDuePeriod);
        }
        
        address _asset = repaymentConstants[_poolID].repayAsset;

        if (_asset == address(0)) {
            require(_amountRequired <= msg.value,
                    "Repayments::repayAmount amount does not match message value.");
            payable(address(_poolID)).transfer(_amountRequired);
        } 
        else {
            IERC20(_asset).transferFrom(msg.sender, _poolID, _amountRequired);
        }

        if (_asset == address(0)) {
            if (msg.value > _amountRequired) {
                payable(address(msg.sender)).transfer(msg.value.sub(_amountRequired));
            }
        }

    }

    

    function repayPrincipal(address payable _poolID, uint256 _amount) public payable isPoolInitialized {

        IPool _pool = IPool(_poolID);
        uint256 _loanStatus = _pool.getLoanStatus();
        require(_loanStatus == 1,
                "Repayments:repayPrincipal Pool should be active");

        require(repaymentVars[_poolID].repaymentOverdue == 0,
                "Repayments:repayPrincipal Repayment overdue unpaid");

        require(repaymentConstants[_poolID].loanDuration == repaymentVars[_poolID].loanDurationCovered,
                "Repayments:repayPrincipal Unpaid interest");

        uint256 _activePrincipal = _pool.getTotalSupply();
        require(_amount == _activePrincipal,
                "Repayments:repayPrincipal Amount should match the principal");

        address _asset = repaymentConstants[_poolID].repayAsset;

        if (_asset == address(0)) {
            require(_amount == msg.value,
                    "Repayments::repayAmount amount does not match message value.");
            _poolID.transfer(_amount);
        } 
        else {
            IERC20(_asset).transferFrom(msg.sender, _poolID, _amount);
        }

        IPool(_poolID).closeLoan();
    }


    /*
    function getRepaymentPeriodCovered(address poolID) external view override returns(uint256) {
        return repaymentVars[poolID].repaymentPeriodCovered;
    }
    */
    function getTotalRepaidAmount(address poolID)
        external
        view
        override
        returns (uint256)
    {
        return repaymentVars[poolID].totalRepaidAmount;
    }

    /*
    function getRepaymentOverdue(address poolID) external view override returns(uint256) {
        return repaymentVars[poolID].repaymentOverdue;
    }
    */
    function repaymentExtended(address poolID) external override {
        require(
            msg.sender == IPoolFactory(PoolFactory).owner(),
            "Repayments::repaymentExtended - Invalid caller"
        );

        repaymentVars[poolID].isLoanExtensionActive = true;
        uint256 activePrincipal = IPool(poolID).getTotalSupply();

        uint256 interestPerSecond =
            activePrincipal.mul(repaymentConstants[poolID].borrowRate).div(
                yearInSeconds
            );

        uint256 _repaymentOverdue =
            (
                (repaymentConstants[poolID].repaymentInterval).sub(
                    repaymentVars[poolID].repaymentPeriodCovered
                )
            )
                .mul(interestPerSecond);
        repaymentVars[poolID].repaymentOverdue = _repaymentOverdue;
    }

    function getInterestCalculationVars(address poolID)
        external
        view
        override
        returns (uint256, uint256)
    {
        return (
            repaymentVars[poolID].repaymentPeriodCovered,
            repaymentVars[poolID].repaymentOverdue
        );
    }

    // function TotalDueamountLeft() public view{
    //     uint256 intervalsLeft = totalNumberOfRepayments-calculateCurrentPeriod();
    //     return(intervalLeft.mul(amountPerPeriod()));
    // }

    /*function requestExtension(uint256 extensionVoteEndTime)
        external isPoolInitialized
        returns (uint256)
    {
        
    }*/

    //event LoanExtensionRequest(address poolID);

    /*function requestExtension(address poolID)
        external isPoolInitialized
    {
        require(repaymentDetails[poolID].extensionsGranted > extensionVoteEndTime,
                "Borrower : Extension period has ended.");

        repaymentDetails[poolID].extensionRequested = true;

        emit LoanExtensionRequest(poolID);
    }*/

    /*function voteOnExtension(address poolID,
                             address voter,
                             uint256 votingPower,
                             uint256 extensionAcceptanceThreshold)
        external 
        isPoolInitialized 
        returns (uint256, uint256) {
        
        require()

    }

    function resultOfVoting(
        uint256 totalExtensionSupport,
        uint256 extensionVoteEndTime,
        uint256 totalSupply,
        uint256 nextDuePeriod
    ) external isPoolInitialized returns (uint256) {
        
    }

    function updatePoolFactory(address _poolFactory) external onlyOwner {
        poolFactory = IPoolFactory(_poolFactory);
    }

    function updateVotingExtensionlength(uint256 _votingExtensionPeriod) external onlyOwner {
        votingExtensionlength = _votingExtensionPeriod;
    }

    function updateVotingPassRatio(uint256 _votingPassRatio) external onlyOwner {
        votingPassRatio = _votingPassRatio;
    }*/

    //function repayInterest(address _poolID, uint256 _amount) public payable isPoolInitialized {

        //IPool _pool = IPool(_poolID);
        //uint256 _loanStatus = _pool.getLoanStatus();
        //require(_loanStatus == 1,
        //        "Repayments:repayInterest Pool should be active.");

        //require(repaymentVars[_poolID].repaymentOverdue == 0,
        //        "Repayments:repayInterest Repayment overdue unpaid.");

        //uint256 _activePrincipal = _pool.getTotalSupply();

        //uint256 _interestPerSecond = _activePrincipal
        //                             .mul(repaymentConstants[_poolID].borrowRate)
        //                             .div(yearInSeconds);

        //uint256 _loanDurationLeft = repaymentConstants[_poolID].loanDuration
        //                            .sub(repaymentVars[_poolID].loanDurationCovered);

        //uint256 _interestLeft = _interestPerSecond.mul(_loanDurationLeft).div(10**8);

        //require(_amount <= _interestLeft,
        //        "Repayments:repayInterest cannot repay more interest than due.");

        //uint256 _loanDurationCovered = _amount.div(_interestPerSecond).div(10**8);

        //repaymentVars[_poolID].loanDurationCovered = repaymentVars[_poolID].loanDurationCovered
        //                                                .add(_loanDurationCovered);

        //address _asset = repaymentConstants[_poolID].repayAsset;

        //if (_asset == address(0)) {
        //    require(_amount == msg.value,
        //            "Repayments::repayAmount amount does not match message value.");
        //}
        // Note: If ether is sent unnecessarily then that will be sent to savingsAccount
        //ISavingsAccount(savingsAccount).depositTo{value: msg.value}(_amount, _asset, address(0), _poolID);
    //}

    //function repayOverdue(address _poolID, uint256 _amount) public payable isPoolInitialized {

        //IPool _pool = IPool(_poolID);

        //repaymentVars[_poolID].repaymentOverdue = _repaymentOverdue - _amount;

        //address _asset = repaymentConstants[_poolID].repayAsset;

        //if (_asset == address(0)) {
        //    require(_amount == msg.value,
        //            "Repayments::repayAmount amount does not match message value.");
        //}
        // Note: If ether is sent unnecessarily then that will be sent to savingsAccount
        //ISavingsAccount(savingsAccount).depositTo{value: _amount}(_amount, _asset, address(0), _poolID);
    //}
}
