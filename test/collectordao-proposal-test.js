const { expect } = require("chai")
const { ethers } = require("hardhat")
const web3 = require("Web3")

describe("collectorDAO", () => {
  let collectorDAOContract;
  let collectorDAO;
  let owner;
  let member1;
  const MEMBERSHIP_PRICE = '1'
  const MEMBERSHIP_PRICE_BELOW = '0.9'
  const MEMBERSHIP_PRICE_ABOVE = '1.1'

  beforeEach(async () => {
    [owner, member1, member2] = await ethers.getSigners()
    collectorDAOContract = await ethers.getContractFactory("CollectorDAO");
    collectorDAO = await collectorDAOContract.deploy();
    await collectorDAO.deployed();
  })

  it("should allow only a member to contribute", async function () {
    const trx = collectorDAO.connect(member1).join({value: web3.utils.toWei(MEMBERSHIP_PRICE)})
    await expect(trx).to.emit(collectorDAO, 'NewMemberAdded')
  })

  it("should not allow a contribution of more than one ether", async function () {
    const trx = collectorDAO.connect(member1).join({value: web3.utils.toWei(MEMBERSHIP_PRICE_ABOVE)})
    await expect(trx).to.be.revertedWith('CollectorDAO:: insufficient funds')
  })

  it("should not allow a contribution of less than one ether", async function () {
    const trx = collectorDAO.connect(member1).join({value: web3.utils.toWei(MEMBERSHIP_PRICE_BELOW)})
    await expect(trx).to.be.revertedWith('CollectorDAO:: insufficient funds')
  })

  it("should ensure contributor is a member", async function () {
    await collectorDAO.connect(member1).join({value: web3.utils.toWei(MEMBERSHIP_PRICE)})
    await expect(await collectorDAO.isMember(member1.address)).to.equal(true)
  })
})
