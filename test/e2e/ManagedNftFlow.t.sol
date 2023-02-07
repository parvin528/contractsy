pragma solidity 0.8.13;

import "./ExtendedBaseTest.sol";

contract ManagedNftFlow is ExtendedBaseTest {
    LockedManagedReward lockedManagedReward;
    FreeManagedReward freeManagedReward;

    uint256 tokenId;
    uint256 tokenId2;
    uint256 tokenId3;

    function _setUp() public override {
        VELO.approve(address(escrow), TOKEN_1);
        tokenId = escrow.createLock(TOKEN_1, MAX_TIME);
        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1);
        tokenId2 = escrow.createLock(TOKEN_1, MAX_TIME);
        vm.stopPrank();
        vm.startPrank(address(owner3));
        VELO.approve(address(escrow), TOKEN_1);
        tokenId3 = escrow.createLock(TOKEN_1, MAX_TIME);
        vm.stopPrank();
        skip(1);
    }

    function testSimpleManagedNftFlow() public {
        // owner owns nft with id: tokenId with amount: TOKEN_1
        // owner2 owns nft with id: tokenId2 with amount: TOKEN_1
        // owner3 owns nft with id: tokenId3 with amount: TOKEN_1
        // owner4 owns the managed nft: tokenId4

        // epoch 0:
        // create managed nft
        // deposit into managed nft
        // simulate rebases for epoch 0
        uint256 supply = escrow.supply();

        // switch allowedManager to allow owner4 to create managed lock
        vm.prank(address(governor));
        escrow.setAllowedManager(address(owner4));

        vm.prank(address(owner4));
        uint256 mTokenId = escrow.createManagedLockFor(address(owner4));
        lockedManagedReward = LockedManagedReward(escrow.managedToLocked(mTokenId));
        freeManagedReward = FreeManagedReward(escrow.managedToFree(mTokenId));

        escrow.depositManaged(tokenId, mTokenId);

        // check deposit successful
        assertEq(escrow.idToManaged(tokenId), mTokenId);
        assertEq(escrow.weights(tokenId, mTokenId), TOKEN_1);
        assertEq(escrow.balanceOfNFT(tokenId), 0);

        vm.prank(address(owner2));
        escrow.depositManaged(tokenId2, mTokenId);

        assertEq(escrow.idToManaged(tokenId2), mTokenId);
        assertEq(escrow.weights(tokenId2, mTokenId), TOKEN_1);
        assertEq(escrow.balanceOfNFT(tokenId2), 0);

        IVotingEscrow.LockedBalance memory locked;
        locked = escrow.locked(mTokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1 * 2);
        assertEq(locked.end, 126403200);
        locked = escrow.locked(tokenId);
        assertEq(uint256(uint128(locked.amount)), 0);
        assertEq(locked.end, 0);
        locked = escrow.locked(tokenId2);
        assertEq(uint256(uint128(locked.amount)), 0);
        assertEq(locked.end, 0);

        // net supply unchanged
        assertEq(escrow.supply(), supply);

        // test voting
        address[] memory pools = new address[](2);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 10000;
        address[] memory rewards = new address[](2);
        rewards[0] = address(VELO);
        rewards[1] = address(USDC);

        // create velo bribe for next epoch
        _createBribeWithAmount(bribeVotingReward, address(VELO), TOKEN_1 * 2);

        /// total votes:
        /// managed nft: TOKEN_1 * 2
        /// owner3: TOKEN_1 * 2
        vm.prank(address(owner4));
        voter.vote(mTokenId, pools, weights);

        /// owner 3 will vote passively
        vm.prank(address(owner3));
        voter.vote(tokenId3, pools, weights);

        // simulate rebases for epoch 0:
        vm.startPrank(address(owner4));
        VELO.approve(address(escrow), TOKEN_1);
        escrow.increaseAmount(mTokenId, TOKEN_1);
        vm.stopPrank();
        supply += TOKEN_1;

        assertEq(escrow.supply(), supply);
        assertEq(VELO.balanceOf(address(lockedManagedReward)), TOKEN_1);
        assertEq(lockedManagedReward.earned(address(VELO), tokenId), 0);

        // check managed nft token lock increased
        locked = escrow.locked(mTokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1 * 3);
        assertEq(locked.end, 126403200);

        // must be poked after ve balance change or votes in bribe won't update
        voter.poke(mTokenId);

        skipToNextEpoch(1);

        // check depositor has earned rebases
        assertEq(lockedManagedReward.earned(address(VELO), tokenId), TOKEN_1 / 2);
        assertEq(lockedManagedReward.earned(address(VELO), tokenId2), TOKEN_1 / 2);

        // epoch 1:
        // simulate rebase + non-compounded velo rewards

        /// state of gauge votes:
        /// mTokenId contribution: 3 / 4
        /// tokenId3 contribution: 1 / 4

        // collect rewards from bribe
        uint256 pre = VELO.balanceOf(address(owner4));
        vm.prank(address(voter));
        bribeVotingReward.getReward(mTokenId, rewards);
        uint256 post = VELO.balanceOf(address(owner4));
        // allow error band of 1e8 / 1e16 due to voting power rounding in bribe
        assertApproxEqRel(post - pre, ((TOKEN_1 * 2) * 3) / 4, 1e8);

        // distribute reward to managed nft depositors
        vm.startPrank(address(owner4));
        VELO.approve(address(freeManagedReward), TOKEN_1 * 2);
        freeManagedReward.notifyRewardAmount(address(VELO), ((TOKEN_1 * 2) * 3) / 4);
        vm.stopPrank();

        // simulate rebases for epoch 1:
        vm.startPrank(address(owner4));
        VELO.approve(address(escrow), TOKEN_1);
        escrow.increaseAmount(mTokenId, TOKEN_1);
        vm.stopPrank();
        supply += TOKEN_1;

        assertEq(escrow.supply(), supply);
        locked = escrow.locked(mTokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1 * 4);
        // locktime remains unchanged as no deposit / withdraw took place
        assertEq(locked.end, 126403200);

        assertEq(lockedManagedReward.earned(address(VELO), tokenId), TOKEN_1 / 2);
        assertEq(freeManagedReward.earned(address(VELO), tokenId), 0);
        assertEq(lockedManagedReward.earned(address(VELO), tokenId2), TOKEN_1 / 2);
        assertEq(freeManagedReward.earned(address(VELO), tokenId2), 0);

        // create usdc bribe for next epoch
        _createBribeWithAmount(bribeVotingReward, address(USDC), USDC_1);

        voter.poke(mTokenId);

        skipToNextEpoch(1);

        assertEq(lockedManagedReward.earned(address(VELO), tokenId), TOKEN_1);
        assertEq(freeManagedReward.earned(address(VELO), tokenId), ((TOKEN_1 * 2) * 3) / 4 / 2);
        assertEq(lockedManagedReward.earned(address(VELO), tokenId2), TOKEN_1);
        assertEq(freeManagedReward.earned(address(VELO), tokenId2), ((TOKEN_1 * 2) * 3) / 4 / 2);

        // epoch 2:
        // simulate rebase + usdc rewards

        /// state of gauge votes:
        /// mTokenId contribution: 4 / 5
        /// tokenId3 contribution: 1 / 5

        uint256 usdcReward = bribeVotingReward.earned(address(USDC), mTokenId);
        pre = USDC.balanceOf(address(owner4));
        vm.prank(address(voter));
        bribeVotingReward.getReward(mTokenId, rewards);
        post = USDC.balanceOf(address(owner4));
        // allow additional looser error band as USDC is only 6 dec
        assertApproxEqRel(post - pre, (USDC_1 * 4) / 5, 1e15);
        assertEq(post - pre, usdcReward);

        // distribute reward to managed nft depositors
        vm.startPrank(address(owner4));
        USDC.approve(address(freeManagedReward), USDC_1);
        freeManagedReward.notifyRewardAmount(address(USDC), usdcReward);
        vm.stopPrank();

        // simulate rebases for epoch 2:
        vm.startPrank(address(owner4));
        VELO.approve(address(escrow), TOKEN_1);
        escrow.increaseAmount(mTokenId, TOKEN_1);
        vm.stopPrank();
        supply += TOKEN_1;

        /// withdraw from managed nft early
        /// not entitled to rewards distributed this week (both free / locked)
        pre = VELO.balanceOf(address(escrow));
        vm.prank(address(owner2));
        escrow.withdrawManaged(tokenId2);
        post = VELO.balanceOf(address(escrow));

        // check locked rewards transferred to VotingEscrow
        assertEq(post - pre, TOKEN_1);
        // rebase from this week + locked rewards for tokenId
        assertEq(VELO.balanceOf(address(lockedManagedReward)), TOKEN_1 * 2);

        // check nfts are configured correctly
        locked = escrow.locked(tokenId2);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1 * 2);
        assertEq(locked.end, 127612800);

        assertEq(escrow.supply(), supply);
        assertEq(lockedManagedReward.earned(address(VELO), tokenId), TOKEN_1);
        assertEq(freeManagedReward.earned(address(VELO), tokenId), ((TOKEN_1 * 2) * 3) / 4 / 2);
        assertEq(freeManagedReward.earned(address(USDC), tokenId), 0);
        assertEq(lockedManagedReward.earned(address(VELO), tokenId2), 0);
        assertEq(freeManagedReward.earned(address(VELO), tokenId2), ((TOKEN_1 * 2) * 3) / 4 / 2);
        assertEq(freeManagedReward.earned(address(USDC), tokenId2), 0);

        voter.poke(mTokenId);

        // owner 2 claims rewards
        pre = VELO.balanceOf(address(owner2));
        uint256 usdcPre = USDC.balanceOf(address(owner2));
        vm.prank(address(owner2));
        freeManagedReward.getReward(tokenId2, rewards);
        post = VELO.balanceOf(address(owner2));
        uint256 usdcPost = USDC.balanceOf(address(owner2));

        assertEq(post - pre, ((TOKEN_1 * 2) * 3) / 4 / 2);
        assertEq(usdcPost - usdcPre, 0);
        assertEq(freeManagedReward.earned(address(VELO), tokenId2), 0);
        assertEq(freeManagedReward.earned(address(USDC), tokenId2), 0);

        skipToNextEpoch(1);

        // epoch 3:

        /// state of gauge votes:
        /// mTokenId contribution: 3 / 4
        /// tokenId3 contribution: 1 / 4

        // owner receives all rewards, owner2 receives nothing
        assertEq(lockedManagedReward.earned(address(VELO), tokenId), TOKEN_1 * 2);
        assertEq(freeManagedReward.earned(address(VELO), tokenId), ((TOKEN_1 * 2) * 3) / 4 / 2);
        assertEq(freeManagedReward.earned(address(USDC), tokenId), usdcReward);
        assertEq(lockedManagedReward.earned(address(VELO), tokenId2), 0);
        assertEq(freeManagedReward.earned(address(VELO), tokenId2), 0);
        assertEq(freeManagedReward.earned(address(USDC), tokenId2), 0);

        skip(1 hours);

        pre = VELO.balanceOf(address(escrow));
        escrow.withdrawManaged(tokenId);
        post = VELO.balanceOf(address(escrow));

        // check locked rewards transferred to VotingEscrow
        assertEq(post - pre, TOKEN_1 * 2);
        assertEq(lockedManagedReward.earned(address(VELO), tokenId), 0);
        assertEq(VELO.balanceOf(address(lockedManagedReward)), 0);

        // check nfts are configured correctly
        locked = escrow.locked(tokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1 * 3);
        assertEq(locked.end, 128217600);

        locked = escrow.locked(mTokenId);
        assertEq(uint256(uint128(locked.amount)), 0);
        assertEq(locked.end, 128217600);

        skip(1 hours);

        // claim rewards after withdrawal
        pre = VELO.balanceOf(address(owner));
        usdcPre = USDC.balanceOf(address(owner));
        freeManagedReward.getReward(tokenId, rewards);
        post = VELO.balanceOf(address(owner));
        usdcPost = USDC.balanceOf(address(owner));

        assertEq(post - pre, ((TOKEN_1 * 2) * 3) / 4 / 2);
        assertEq(usdcPost - usdcPre, usdcReward);
        assertEq(freeManagedReward.earned(address(VELO), tokenId), 0);
        assertEq(freeManagedReward.earned(address(USDC), tokenId), 0);

        // withdraw managed nft votes from pool
        vm.prank(address(owner4));
        voter.reset(mTokenId);

        skipToNextEpoch(1);

        // epoch 4:
        // test normal operation of nft post-withdrawal

        /// state of gauge votes
        /// tokenId contribution: ~= 3 / 4
        /// tokenId3 contribution: ~= 1 / 4

        // owner votes for pair now
        voter.vote(tokenId, pools, weights);

        // create velo bribe for epoch 4
        _createBribeWithAmount(bribeVotingReward, address(VELO), TOKEN_1);

        skipToNextEpoch(1);

        // test normal nft behavior post withdrawal
        // ~= approx TOKEN_1 * 3 / 4, some drift due to voting power decay
        assertEq(bribeVotingReward.earned(address(VELO), tokenId), 749095297039448925);

        pre = VELO.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(tokenId, rewards);
        post = VELO.balanceOf(address(owner));

        assertEq(post - pre, 749095297039448925);
    }

    function testTransferManagedNftFlow() public {
        // epoch 0:
        // create managed nft
        // deposit into managed nft
        // simulate rebases for epoch 0
        uint256 supply = escrow.supply();

        // switch allowedManager to allow owner4 to create managed lock
        vm.prank(address(governor));
        escrow.setAllowedManager(address(owner4));

        vm.prank(address(owner4));
        uint256 mTokenId = escrow.createManagedLockFor(address(owner4));
        lockedManagedReward = LockedManagedReward(escrow.managedToLocked(mTokenId));
        freeManagedReward = FreeManagedReward(escrow.managedToFree(mTokenId));

        escrow.depositManaged(tokenId, mTokenId);

        // check deposit successful
        assertEq(escrow.idToManaged(tokenId), mTokenId);
        assertEq(escrow.weights(tokenId, mTokenId), TOKEN_1);
        assertEq(escrow.balanceOfNFT(tokenId), 0);

        vm.prank(address(owner2));
        escrow.depositManaged(tokenId2, mTokenId);

        assertEq(escrow.idToManaged(tokenId2), mTokenId);
        assertEq(escrow.weights(tokenId2, mTokenId), TOKEN_1);
        assertEq(escrow.balanceOfNFT(tokenId2), 0);

        IVotingEscrow.LockedBalance memory locked;
        locked = escrow.locked(mTokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1 * 2);
        assertEq(locked.end, 126403200);
        locked = escrow.locked(tokenId);
        assertEq(uint256(uint128(locked.amount)), 0);
        assertEq(locked.end, 0);
        locked = escrow.locked(tokenId2);
        assertEq(uint256(uint128(locked.amount)), 0);
        assertEq(locked.end, 0);

        // net supply unchanged
        assertEq(escrow.supply(), supply);

        // test voting
        address[] memory pools = new address[](2);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 10000;
        address[] memory rewards = new address[](2);
        rewards[0] = address(VELO);
        rewards[1] = address(USDC);

        // create velo bribe for next epoch
        _createBribeWithAmount(bribeVotingReward, address(VELO), TOKEN_1);

        vm.prank(address(owner4));
        voter.vote(mTokenId, pools, weights);

        skipToNextEpoch(1);

        // epoch 1:
        // reset managed nft
        // transfer managed nft to new owner

        // collect rewards from bribe
        uint256 pre = VELO.balanceOf(address(owner4));
        vm.prank(address(voter));
        bribeVotingReward.getReward(mTokenId, rewards);
        uint256 post = VELO.balanceOf(address(owner4));
        assertEq(post - pre, TOKEN_1);

        // distribute reward to managed nft depositors
        vm.startPrank(address(owner4));
        VELO.approve(address(freeManagedReward), TOKEN_1 * 2);
        freeManagedReward.notifyRewardAmount(address(VELO), TOKEN_1);
        vm.stopPrank();

        vm.startPrank(address(owner4));
        voter.reset(mTokenId);
        escrow.transferFrom(address(owner4), address(owner3), mTokenId);
        vm.stopPrank();

        // required to overcome flash nft protection after transfer
        vm.roll(block.timestamp + 1);

        skipToNextEpoch(1);

        // epoch 2:
        // managed nft votes for pool again

        assertEq(freeManagedReward.earned(address(VELO), tokenId), TOKEN_1 / 2);
        assertEq(freeManagedReward.earned(address(VELO), tokenId2), TOKEN_1 / 2);

        // create velo bribe for next epoch
        _createBribeWithAmount(bribeVotingReward, address(VELO), TOKEN_1 * 2);

        // user withdraws from nft
        pre = VELO.balanceOf(address(escrow));
        escrow.withdrawManaged(tokenId);
        post = VELO.balanceOf(address(escrow));

        assertEq(post - pre, 0);

        // check nfts are configured correctly
        locked = escrow.locked(tokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1);
        assertEq(locked.end, 127612800);

        locked = escrow.locked(mTokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1);
        assertEq(locked.end, 127612800);

        skip(1 hours);

        vm.prank(address(owner3));
        voter.vote(mTokenId, pools, weights);

        skipToNextEpoch(1);

        // epoch 3:
        // claim and distribute rewards

        assertEq(freeManagedReward.earned(address(VELO), tokenId), TOKEN_1 / 2);
        assertEq(freeManagedReward.earned(address(VELO), tokenId2), TOKEN_1 / 2);

        skipAndRoll(1);
        escrow.setManagedState(mTokenId, true);
        // normal operation despite managed nft can no longer accept new deposits

        // collect rewards from bribe
        pre = VELO.balanceOf(address(owner3));
        vm.prank(address(voter));
        bribeVotingReward.getReward(mTokenId, rewards);
        post = VELO.balanceOf(address(owner3));
        assertEq(post - pre, TOKEN_1 * 2);

        // distribute reward to managed nft depositors
        vm.startPrank(address(owner3));
        VELO.approve(address(freeManagedReward), TOKEN_1 * 2);
        freeManagedReward.notifyRewardAmount(address(VELO), TOKEN_1 * 2);
        vm.stopPrank();

        skipToNextEpoch(1);

        // epoch 4:

        assertEq(freeManagedReward.earned(address(VELO), tokenId), TOKEN_1 / 2);
        assertEq(freeManagedReward.earned(address(VELO), tokenId2), (TOKEN_1 * 5) / 2);

        pre = VELO.balanceOf(address(escrow));
        vm.prank(address(owner2));
        escrow.withdrawManaged(tokenId2);
        post = VELO.balanceOf(address(escrow));

        assertEq(post - pre, 0);
    }
}