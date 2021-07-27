import hardhat from "hardhat";

async function main() {
    console.log("deploy start")

    const SixElements = await hardhat.ethers.getContractFactory("SixElements")
    const sixElements = await SixElements.deploy("0x44F3747017Cc79a0D55914C20bf6666194359CD7")
    console.log(`6 Elements address: ${sixElements.address}`)
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
