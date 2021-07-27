// SPDX-License-Identifier: MIT
pragma solidity ^0.8.5;

interface IElementMaids {

    enum ElementKind {Light, Fire, Water, Wind, Earth, Dark}

    event BuyEnergy(address player, uint256 quantity);
    event UseEnergy(address player, uint256 quantity);
    event JoinGame(address player, uint8 x, uint8 y, ElementKind kind, uint8 unitCount);
    event CreateArmy(address player, uint8 x, uint8 y, ElementKind kind, uint8 unitCount);
    event AppendUnits(address player, uint8 x, uint8 y, uint8 unitCount);
    event Attack(address player, uint8 fromX, uint8 fromY, uint8 toX, uint8 toY);
    event Support(address supporter, address to, uint256 quantity);
    event EndSeason(uint256 season, address winner);

    function buyEnergy(uint256 coinAmount) external;
    function buyEnergyWithPermit(
        uint256 coinAmount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    
    function createArmy(uint8 x, uint8 y, ElementKind kind, uint8 unitCount, uint256 coinAmount) external;
    function createArmyWithPermit(
        uint8 x, uint8 y, ElementKind kind, uint8 unitCount, uint256 coinAmount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function appendUnits(uint8 x, uint8 y, uint8 unitCount, uint256 coinAmount) external;
    function appendUnitsWithPermit(
        uint8 x, uint8 y, uint8 unitCount, uint256 coinAmount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function attack(uint8 fromX, uint8 fromY, uint8 toX, uint8 toY) external;
    
    function support(address to, uint256 quantity, uint256 coinAmount) external;
    function supportWithPermit(
        address to, uint256 quantity, uint256 coinAmount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function supporterWithdraw(uint256 targetSeason) external;
}
