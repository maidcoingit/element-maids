// SPDX-License-Identifier: MIT
pragma solidity ^0.8.5;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./interfaces/IElementMaids.sol";
import "./interfaces/IMaidCoin.sol";

contract ElementMaids is Ownable, IElementMaids {
    uint256 public constant ENERGY_PRICE = 1e14;
    uint8 public constant BASE_SUMMON_ENERGY = 10;
    uint8 public constant MAP_W = 8;
    uint8 public constant MAP_H = 8;
    uint8 public constant MAX_UNIT_COUNT = 30;
    uint8 public constant MAX_ENTER_COUNT_PER_BLOCK = 8;

    IMaidCoin public immutable maidCoin;
    IERC721 public immutable maid;
    mapping(address => uint256) public energies;

    constructor(IMaidCoin _maidCoin, IERC721 _maid) {
        maidCoin = _maidCoin;
        maid = _maid;
    }

    mapping(ElementKind => uint256[]) public elementMaids;

    function addElementMaid(ElementKind kind, uint256 maidId) external onlyOwner {
        elementMaids[kind].push(maidId);
    }

    function removeElementMaid(ElementKind kind, uint256 maidId) external onlyOwner {
        uint256[] storage maids = elementMaids[kind];
        uint256 maidsLength = maids.length;
        for (uint256 i = 0; i < maidsLength; i += 1) {
            if (maids[i] == maidId) {
                maids[i] = maids[maidsLength - 1];
                maids.pop();
                break;
            }
        }
    }

    mapping (address => mapping (ElementKind => bool)) private checkMyMaid;

    function setMaidChecking(ElementKind[] memory kinds, bool[] memory settings) external {
        require(kinds.length == settings.length);
        uint256 length = kinds.length;
        for (uint256 i = 0; i < length; i += 1) {
            checkMyMaid[msg.sender][kinds[i]] = settings[i];
        }
    }

    struct Army {
        ElementKind kind;
        uint8 unitCount;
        address owner;
        uint256 blockNumber;
    }
    Army[MAP_H][MAP_W] public map;

    struct WinnerInfo {
        address winner;
        uint256 winnerReward;
        uint256 winnerEnergyUsed;
        uint256 winnerEnergyTaken;
    }

    struct PlayerInfo {
        uint256 energyUsed;
        uint256 energyTaken;
        uint8 occupyCounts;
        uint256 lastEnterBlock;
    }

    struct SupporterInfo {
        mapping(address => uint256) energySupported;
        bool supporterWithdrawns;
    }

    uint256 public season = 0;
    mapping(uint256 => uint256) public rewards;
    mapping(uint256 => WinnerInfo) public winnerInfo;
    mapping(uint256 => mapping(address => PlayerInfo)) public playerInfo;
    mapping(uint256 => mapping(address => SupporterInfo)) public supporterInfo;
    mapping(uint256 => uint8) public enterCountsPerBlock;

    function buyEnergy(uint256 coinAmount) public override {
        uint256 quantity = coinAmount / ENERGY_PRICE;
        require(quantity > 0, "Only buy more than zero amount");
        maidCoin.transferFrom(msg.sender, address(this), coinAmount);

        energies[msg.sender] += quantity;
        uint256 burning = coinAmount / 20;
        rewards[season] += (coinAmount - burning);
        maidCoin.burn(burning); // 5% to burn.

        emit BuyEnergy(msg.sender, quantity);
    }

    function buyEnergyWithPermit(
        uint256 coinAmount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override {
        maidCoin.permit(msg.sender, address(this), coinAmount, deadline, v, r, s);
        buyEnergy(coinAmount);
    }

    function useEnergy(uint256 _season, uint8 unitCount) internal {
        uint256 energyNeed = unitCount * (BASE_SUMMON_ENERGY + _season);
        energies[msg.sender] -= energyNeed;
        playerInfo[_season][msg.sender].energyUsed += energyNeed;
        emit UseEnergy(msg.sender, energyNeed);
    }

    function createArmy(
        uint8 x,
        uint8 y,
        ElementKind kind,
        uint8 unitCount,
        uint256 coinAmount
    ) public override {
        require(msg.sender == tx.origin, "Must be EOA");
        require(map[y][x].owner == address(0), "This space is not empty");
        require(unitCount <= MAX_UNIT_COUNT, "Exceeds max unit counts per space");

        uint256 _season = season;
        PlayerInfo storage _playerInfo = playerInfo[_season][msg.sender];
        // enter
        if (_playerInfo.occupyCounts == 0) {
            uint8 _enterCountsPerBlock = enterCountsPerBlock[block.number];
            require(_enterCountsPerBlock <= MAX_ENTER_COUNT_PER_BLOCK, "Exceeds max enter counts per block");

            if (coinAmount > 0) buyEnergy(coinAmount);
            useEnergy(_season, unitCount);

            map[y][x] = Army({kind: kind, unitCount: unitCount, owner: msg.sender, blockNumber: block.number});
            _playerInfo.occupyCounts = 1;

            enterCountsPerBlock[block.number] = _enterCountsPerBlock + 1;
            _playerInfo.lastEnterBlock = block.number;

            emit JoinGame(msg.sender, x, y, kind, unitCount);
        } else {
            // check if there are allies nearby.
            require(
                ((x >= 1 && map[y][x - 1].owner == msg.sender) ||
                    (y >= 1 && map[y - 1][x].owner == msg.sender) ||
                    (x < MAP_W - 1 && map[y][x + 1].owner == msg.sender) ||
                    (y < MAP_H - 1 && map[y + 1][x].owner == msg.sender)) &&
                    (_playerInfo.lastEnterBlock != block.number),
                "Only summon next to space occupied by your army"
            );

            if (coinAmount > 0) buyEnergy(coinAmount);
            useEnergy(_season, unitCount);

            map[y][x] = Army({kind: kind, unitCount: unitCount, owner: msg.sender, blockNumber: block.number});
            _playerInfo.occupyCounts += 1;

            emit CreateArmy(msg.sender, x, y, kind, unitCount);

            // win.
            if (_playerInfo.occupyCounts == MAP_W * MAP_H) {
                uint256 _energyUsed = _playerInfo.energyUsed;
                uint256 _energyTaken = _playerInfo.energyTaken;

                uint256 winnerReward;

                //Guarantee a winner 30% of rewards.
                if (7 * _energyUsed < 3 * _energyTaken) winnerReward = (rewards[_season] * 3) / 10;
                else winnerReward = (rewards[_season] * _energyUsed) / (_energyUsed + _energyTaken);

                emit EndSeason(_season, msg.sender);

                delete map;
                season = _season + 1;

                winnerInfo[_season] = WinnerInfo({
                    winner: msg.sender,
                    winnerReward: winnerReward,
                    winnerEnergyUsed: _energyUsed,
                    winnerEnergyTaken: _energyTaken
                });

                maidCoin.transfer(msg.sender, winnerReward);
            }
        }
    }

    function createArmyWithPermit(
        uint8 x,
        uint8 y,
        ElementKind kind,
        uint8 unitCount,
        uint256 coinAmount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override {
        maidCoin.permit(msg.sender, address(this), coinAmount, deadline, v, r, s);
        createArmy(x, y, kind, unitCount, coinAmount);
    }

    function appendUnits(
        uint8 x,
        uint8 y,
        uint8 unitCount,
        uint256 coinAmount
    ) public override {
        require(map[y][x].owner == msg.sender, "Only append to your army");

        uint8 newUnitCount = map[y][x].unitCount + unitCount;
        require(newUnitCount <= MAX_UNIT_COUNT, "Exceeds max unit counts per space");

        if (coinAmount > 0) buyEnergy(coinAmount);
        useEnergy(season, unitCount);

        map[y][x].unitCount = newUnitCount;
        map[y][x].blockNumber = block.number;
        emit AppendUnits(msg.sender, x, y, unitCount);
    }

    function appendUnitsWithPermit(
        uint8 x,
        uint8 y,
        uint8 unitCount,
        uint256 coinAmount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        maidCoin.permit(msg.sender, address(this), coinAmount, deadline, v, r, s);
        appendUnits(x, y, unitCount, coinAmount);
    }

    function calculateDamage(Army memory from, Army memory to) internal view returns (uint8) {
        uint16 damage = from.unitCount;

        if (checkMyMaid[from.owner][from.kind]) {
            uint256[] memory maids = elementMaids[from.kind];
            uint256 maidsLength = maids.length;
            for (uint256 i = 0; i < maidsLength; i += 1) {
                if (maid.ownerOf(maids[i]) == from.owner) {
                    damage = (damage * 125) / 100; // *1.25
                    break;
                }
            }
        }

        // Light -> *2 -> Dark
        // Light -> /1.25 -> Fire, Water, Wind, Earth
        if (from.kind == ElementKind.Light) {
            if (to.kind == ElementKind.Dark) {
                damage *= 2;
            } else if (
                to.kind == ElementKind.Fire ||
                to.kind == ElementKind.Water ||
                to.kind == ElementKind.Wind ||
                to.kind == ElementKind.Earth
            ) {
                damage = (damage * 100) / 125;
            }
        }
        // Dark -> *1.25 -> Fire, Water, Wind, Earth
        // Dark -> /2 -> Light
        else if (from.kind == ElementKind.Dark) {
            if (
                to.kind == ElementKind.Fire ||
                to.kind == ElementKind.Water ||
                to.kind == ElementKind.Wind ||
                to.kind == ElementKind.Earth
            ) {
                damage = (damage * 125) / 100;
            } else if (to.kind == ElementKind.Light) {
                damage /= 2;
            }
        }
        // Fire, Water, Wind, Earth -> *1.25 -> Light
        else if (to.kind == ElementKind.Light) {
            damage = (damage * 125) / 100;
        }
        // Fire, Water, Wind, Earth -> /1.25 -> Dark
        else if (to.kind == ElementKind.Dark) {
            damage = (damage * 100) / 125;
        }
        // Fire -> *1.5 -> Wind
        // Wind -> *1.5 -> Earth
        // Earth -> *1.5 -> Water
        // Water -> *1.5 -> Fire
        else if (
            (from.kind == ElementKind.Fire && to.kind == ElementKind.Wind) ||
            (from.kind == ElementKind.Wind && to.kind == ElementKind.Earth) ||
            (from.kind == ElementKind.Earth && to.kind == ElementKind.Water) ||
            (from.kind == ElementKind.Water && to.kind == ElementKind.Fire)
        ) {
            damage = (damage * 15) / 10;
        }
        // Wind -> /1.5 -> Fire
        // Earth -> /1.5 -> Wind
        // Water -> /1.5 -> Earth
        // Fire -> /1.5 -> Water
        else if (
            (from.kind == ElementKind.Wind && to.kind == ElementKind.Fire) ||
            (from.kind == ElementKind.Earth && to.kind == ElementKind.Wind) ||
            (from.kind == ElementKind.Water && to.kind == ElementKind.Earth) ||
            (from.kind == ElementKind.Fire && to.kind == ElementKind.Water)
        ) {
            damage = (damage * 10) / 15;
        }

        return uint8(damage);
    }

    function attack(
        uint8 fromX,
        uint8 fromY,
        uint8 toX,
        uint8 toY
    ) external override {
        require((fromX < toX ? toX - fromX : fromX - toX) + (fromY < toY ? toY - fromY : fromY - toY) == 1);

        Army storage from = map[fromY][fromX];
        Army storage to = map[toY][toX];

        require(from.owner == msg.sender);
        require(from.blockNumber < block.number, "Wait until next block to attack");

        // move.
        if (to.owner == address(0)) {
            map[toY][toX] = from;
            to.blockNumber = block.number;
            delete map[fromY][fromX];
        }
        // combine.
        else if (to.owner == msg.sender) {
            require(to.kind == from.kind);

            uint8 newUnitCount = to.unitCount + from.unitCount;
            require(newUnitCount <= MAX_UNIT_COUNT, "Exceeds max unit counts per space");

            to.unitCount = newUnitCount;
            to.blockNumber = block.number;
            playerInfo[season][msg.sender].occupyCounts -= 1;
            delete map[fromY][fromX];
        }
        // attack.
        else {
            uint8 fromDamage = calculateDamage(from, to);
            uint8 toDamage = calculateDamage(to, from);

            if (fromDamage >= to.unitCount) {
                playerInfo[season][to.owner].occupyCounts -= 1;
                delete map[toY][toX];
            } else {
                to.unitCount -= fromDamage;
            }

            if (toDamage >= from.unitCount) {
                playerInfo[season][msg.sender].occupyCounts -= 1;
                delete map[fromY][fromX];
            } else {
                from.unitCount -= toDamage;
            }

            // occupy.
            if (from.owner == msg.sender && to.owner == address(0)) {
                map[toY][toX] = from;
                to.blockNumber = block.number;
                delete map[fromY][fromX];
            }
        }

        emit Attack(msg.sender, fromX, fromY, toX, toY);
    }

    function support(
        address to,
        uint256 quantity,
        uint256 coinAmount
    ) public override {
        require(msg.sender == tx.origin, "Must be EOA");
        PlayerInfo storage _playerInfo = playerInfo[season][to];
        require(_playerInfo.occupyCounts <= (MAP_W * MAP_H) / 2, "The player occupies over 50% of map");
        if (coinAmount > 0) buyEnergy(coinAmount);

        energies[msg.sender] -= quantity;
        energies[to] += quantity;
        _playerInfo.energyTaken += quantity;
        supporterInfo[season][msg.sender].energySupported[to] += quantity;
        emit UseEnergy(msg.sender, quantity);
        emit Support(msg.sender, to, quantity);
    }

    function supportWithPermit(
        address to,
        uint256 quantity,
        uint256 coinAmount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        maidCoin.permit(msg.sender, address(this), coinAmount, deadline, v, r, s);
        support(to, quantity, coinAmount);
    }

    function supporterWithdraw(uint256 targetSeason) external override {
        require(targetSeason < season);
        SupporterInfo storage sInfo = supporterInfo[targetSeason][msg.sender];
        require(!sInfo.supporterWithdrawns);
        sInfo.supporterWithdrawns = true;

        WinnerInfo storage _winnerInfo = winnerInfo[targetSeason];
        uint256 supporterReward = ((rewards[targetSeason] - _winnerInfo.winnerReward) *
            sInfo.energySupported[_winnerInfo.winner]) / _winnerInfo.winnerEnergyTaken;

        maidCoin.transfer(msg.sender, supporterReward);
    }
}
