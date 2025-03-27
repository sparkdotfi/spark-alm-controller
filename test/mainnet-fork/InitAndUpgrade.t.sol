// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "test/mainnet-fork/ForkTestBase.t.sol";

import { IRateLimits } from "src/interfaces/IRateLimits.sol";

import { ControllerInstance }      from "../../deploy/ControllerInstance.sol";
import { MainnetControllerDeploy } from "../../deploy/ControllerDeploy.sol";

import { MainnetControllerInit as Init } from "../../deploy/MainnetControllerInit.sol";

// Necessary to get error message assertions to work
contract LibraryWrapper {

    function initAlmSystem(
        address vault,
        address usds,
        ControllerInstance       memory controllerInst,
        Init.ConfigAddressParams memory configAddresses,
        Init.CheckAddressParams  memory checkAddresses
    )
        external
    {
        Init.initAlmSystem(vault, usds, controllerInst, configAddresses, checkAddresses);
    }

    function upgradeController(
        ControllerInstance       memory controllerInst,
        Init.ConfigAddressParams memory configAddresses,
        Init.CheckAddressParams  memory checkAddresses
    )
        external
    {
        Init.upgradeController(controllerInst, configAddresses, checkAddresses);
    }

    function pauseProxyInitAlmSystem(address psm, address almProxy) external {
        Init.pauseProxyInitAlmSystem(psm, almProxy);
    }

}

contract MainnetControllerInitAndUpgradeTestBase is ForkTestBase {

    function _getDefaultParams()
        internal view returns (
            Init.ConfigAddressParams memory configAddresses,
            Init.CheckAddressParams  memory checkAddresses
        )
    {
        configAddresses = Init.ConfigAddressParams({
            freezer       : freezer,
            relayer       : relayer,
            oldController : address(0)
        });

        checkAddresses = Init.CheckAddressParams({
            admin      : Ethereum.SPARK_PROXY,
            proxy      : address(almProxy),
            rateLimits : address(rateLimits),
            vault      : address(vault),
            psm        : Ethereum.PSM,
            daiUsds    : Ethereum.DAI_USDS
        });
    }

}

contract MainnetControllerInitAndUpgradeFailureTest is MainnetControllerInitAndUpgradeTestBase {

    // NOTE: `initAlmSystem` and `upgradeController` are tested in the same contract because
    //       they both use _initController and have similar specific setups, so it
    //       less complex/repetitive to test them together.

    LibraryWrapper wrapper;

    ControllerInstance public controllerInst;

    address public mismatchAddress = makeAddr("mismatchAddress");

    address public oldController;

    Init.ConfigAddressParams configAddresses;
    Init.CheckAddressParams  checkAddresses;

    function setUp() public override {
        super.setUp();

        oldController = address(mainnetController);  // Cache for later testing

        // NOTE: initAlmSystem will redundantly call rely and approve on already inited
        //       almProxy and rateLimits, this setup was chosen to easily test upgrade and init failures.
        //       It also should be noted that the almProxy and rateLimits that are being used in initAlmSystem
        //       are already deployed. This is technically possible to do and works in the same way, it was
        //       done also for make testing easier.
        mainnetController = MainnetController(MainnetControllerDeploy.deployController({
            admin      : Ethereum.SPARK_PROXY,
            almProxy   : address(almProxy),
            rateLimits : address(rateLimits),
            vault      : address(vault),
            psm        : Ethereum.PSM,
            daiUsds    : Ethereum.DAI_USDS
        }));

        ( configAddresses, checkAddresses ) = _getDefaultParams();

        controllerInst = ControllerInstance({
            almProxy   : address(almProxy),
            controller : address(mainnetController),
            rateLimits : address(rateLimits)
        });

        // Admin will be calling the library from its own address
        vm.etch(SPARK_PROXY, address(new LibraryWrapper()).code);

        wrapper = LibraryWrapper(SPARK_PROXY);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 21430000;  // Dec 18, 2024
    }

    /**********************************************************************************************/
    /*** ACL tests                                                                              ***/
    /**********************************************************************************************/

    function test_initAlmSystem_incorrectAdminAlmProxy() external {
        vm.prank(SPARK_PROXY);
        almProxy.revokeRole(DEFAULT_ADMIN_ROLE, SPARK_PROXY);

        vm.expectRevert("MainnetControllerInit/incorrect-admin-almProxy");
        wrapper.initAlmSystem(
            vault,
            address(usds),
            controllerInst,
            configAddresses,
            checkAddresses
        );
    }

    function test_initAlmSystem_incorrectAdminRateLimits() external {
        vm.prank(SPARK_PROXY);
        rateLimits.revokeRole(DEFAULT_ADMIN_ROLE, SPARK_PROXY);

        vm.expectRevert("MainnetControllerInit/incorrect-admin-rateLimits");
        wrapper.initAlmSystem(
            vault,
            address(usds),
            controllerInst,
            configAddresses,
            checkAddresses
        );
    }

    function test_initAlmSystem_upgradeController_incorrectAdminController() external {
        vm.prank(SPARK_PROXY);
        mainnetController.revokeRole(DEFAULT_ADMIN_ROLE, SPARK_PROXY);

        _checkInitAndUpgradeFail(abi.encodePacked("MainnetControllerInit/incorrect-admin-controller"));
    }

    /**********************************************************************************************/
    /*** Constructor tests                                                                      ***/
    /**********************************************************************************************/

    function test_initAlmSystem_upgradeController_incorrectAlmProxy() external {
        // Deploy new address that will not EVM revert on OZ ACL check
        controllerInst.almProxy = address(new ALMProxy(SPARK_PROXY));

        _checkInitAndUpgradeFail(abi.encodePacked("MainnetControllerInit/incorrect-almProxy"));
    }

    function test_initAlmSystem_upgradeController_incorrectRateLimits() external {
        // Deploy new address that will not EVM revert on OZ ACL check
        controllerInst.rateLimits = address(new RateLimits(SPARK_PROXY));

        _checkInitAndUpgradeFail(abi.encodePacked("MainnetControllerInit/incorrect-rateLimits"));
    }

    function test_initAlmSystem_upgradeController_incorrectVault() external {
        checkAddresses.vault = mismatchAddress;
        _checkInitAndUpgradeFail(abi.encodePacked("MainnetControllerInit/incorrect-vault"));
    }

    function test_initAlmSystem_upgradeController_incorrectPsm() external {
        checkAddresses.psm = mismatchAddress;
        _checkInitAndUpgradeFail(abi.encodePacked("MainnetControllerInit/incorrect-psm"));
    }

    function test_initAlmSystem_upgradeController_incorrectDaiUsds() external {
        checkAddresses.daiUsds = mismatchAddress;
        _checkInitAndUpgradeFail(abi.encodePacked("MainnetControllerInit/incorrect-daiUsds"));
    }

    function test_initAlmSystem_upgradeController_oldControllerIsNewController() external {
        configAddresses.oldController = controllerInst.controller;
        _checkInitAndUpgradeFail(abi.encodePacked("MainnetControllerInit/old-controller-is-new-controller"));
    }

    /**********************************************************************************************/
    /*** Upgrade tests                                                                          ***/
    /**********************************************************************************************/

    function test_upgradeController_oldControllerZeroAddress() external {
        configAddresses.oldController = address(0);

        vm.expectRevert("MainnetControllerInit/old-controller-zero-address");
        wrapper.upgradeController(
            controllerInst,
            configAddresses,
            checkAddresses
        );
    }

    function test_upgradeController_oldControllerDoesNotHaveRoleInAlmProxy() external {
        configAddresses.oldController = oldController;

        // Revoke the old controller address in ALM proxy
        vm.startPrank(SPARK_PROXY);
        almProxy.revokeRole(almProxy.CONTROLLER(), configAddresses.oldController);
        vm.stopPrank();

        // Try to upgrade with the old controller address that is doesn't have the CONTROLLER role
        vm.expectRevert("MainnetControllerInit/old-controller-not-almProxy-controller");
        wrapper.upgradeController(
            controllerInst,
            configAddresses,
            checkAddresses
        );
    }

    function test_upgradeController_oldControllerDoesNotHaveRoleInRateLimits() external {
        configAddresses.oldController = oldController;

        // Revoke the old controller address in rate limits
        vm.startPrank(SPARK_PROXY);
        rateLimits.revokeRole(rateLimits.CONTROLLER(), configAddresses.oldController);
        vm.stopPrank();

        // Try to upgrade with the old controller address that is doesn't have the CONTROLLER role
        vm.expectRevert("MainnetControllerInit/old-controller-not-rateLimits-controller");
        wrapper.upgradeController(
            controllerInst,
            configAddresses,
            checkAddresses
        );
    }

    /**********************************************************************************************/
    /*** Helper functions                                                                       ***/
    /**********************************************************************************************/

    function _checkInitAndUpgradeFail(bytes memory expectedError) internal {
        vm.expectRevert(expectedError);
        wrapper.initAlmSystem(
            vault,
            address(usds),
            controllerInst,
            configAddresses,
            checkAddresses
        );

        vm.expectRevert(expectedError);
        wrapper.upgradeController(
            controllerInst,
            configAddresses,
            checkAddresses
        );
    }

}

contract MainnetControllerInitAlmSystemSuccessTests is MainnetControllerInitAndUpgradeTestBase {

    LibraryWrapper wrapper;

    ControllerInstance public controllerInst;

    address public mismatchAddress = makeAddr("mismatchAddress");

    Init.ConfigAddressParams configAddresses;
    Init.CheckAddressParams  checkAddresses;

    function setUp() public override {
        super.setUp();

        controllerInst = MainnetControllerDeploy.deployFull(
            Ethereum.SPARK_PROXY,
            address(vault),
            Ethereum.PSM,
            Ethereum.DAI_USDS
        );

        // Overwrite storage for all previous deployments in setUp and assert brand new deployment
        mainnetController = MainnetController(controllerInst.controller);
        almProxy          = ALMProxy(payable(controllerInst.almProxy));
        rateLimits        = RateLimits(controllerInst.rateLimits);

        ( configAddresses, checkAddresses ) = _getDefaultParams();

        // Admin will be calling the library from its own address
        vm.etch(SPARK_PROXY, address(new LibraryWrapper()).code);

        wrapper = LibraryWrapper(SPARK_PROXY);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 21430000;  // Dec 18, 2024
    }

    function test_initAlmSystem() public {
        assertEq(mainnetController.hasRole(mainnetController.FREEZER(), freezer), false);
        assertEq(mainnetController.hasRole(mainnetController.RELAYER(), relayer), false);

        assertEq(almProxy.hasRole(almProxy.CONTROLLER(), address(mainnetController)),     false);
        assertEq(rateLimits.hasRole(rateLimits.CONTROLLER(), address(mainnetController)), false);

        assertEq(IVaultLike(vault).wards(controllerInst.almProxy), 0);
        assertEq(usds.allowance(buffer, controllerInst.almProxy),  0);

        vm.startPrank(SPARK_PROXY);
        wrapper.initAlmSystem(
            address(vault),
            address(usds),
            controllerInst,
            configAddresses,
            checkAddresses
        );

        assertEq(mainnetController.hasRole(mainnetController.FREEZER(), freezer), true);
        assertEq(mainnetController.hasRole(mainnetController.RELAYER(), relayer), true);

        assertEq(almProxy.hasRole(almProxy.CONTROLLER(), address(mainnetController)),     true);
        assertEq(rateLimits.hasRole(rateLimits.CONTROLLER(), address(mainnetController)), true);

        assertEq(IVaultLike(vault).wards(controllerInst.almProxy), 1);
        assertEq(usds.allowance(buffer, controllerInst.almProxy),  type(uint256).max);
    }

    function test_pauseProxyInitAlmSystem() public {
        // Update to call the library from the pause proxy
        vm.etch(PAUSE_PROXY, address(new LibraryWrapper()).code);
        wrapper = LibraryWrapper(PAUSE_PROXY);

        assertEq(IPSMLike(Ethereum.PSM).bud(controllerInst.almProxy), 0);

        vm.startPrank(PAUSE_PROXY);
        wrapper.pauseProxyInitAlmSystem(Ethereum.PSM, controllerInst.almProxy);
        vm.stopPrank();

        assertEq(IPSMLike(Ethereum.PSM).bud(controllerInst.almProxy), 1);
    }

}

contract MainnetControllerUpgradeControllerSuccessTests is MainnetControllerInitAndUpgradeTestBase {

    LibraryWrapper wrapper;

    ControllerInstance public controllerInst;

    address public mismatchAddress = makeAddr("mismatchAddress");

    Init.ConfigAddressParams configAddresses;
    Init.CheckAddressParams  checkAddresses;

    MainnetController newController;

    function setUp() public override {
        super.setUp();

        ( configAddresses, checkAddresses ) = _getDefaultParams();

        newController = MainnetController(MainnetControllerDeploy.deployController({
            admin      : Ethereum.SPARK_PROXY,
            almProxy   : address(almProxy),
            rateLimits : address(rateLimits),
            vault      : address(vault),
            psm        : Ethereum.PSM,
            daiUsds    : Ethereum.DAI_USDS
        }));

        controllerInst = ControllerInstance({
            almProxy   : address(almProxy),
            controller : address(newController),
            rateLimits : address(rateLimits)
        });

        configAddresses.oldController = address(mainnetController);  // Revoke from old controller

        // Admin will be calling the library from its own address
        vm.etch(SPARK_PROXY, address(new LibraryWrapper()).code);

        wrapper = LibraryWrapper(SPARK_PROXY);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 21430000;  // Dec 18, 2024
    }

    function test_upgradeController() public {
        assertEq(newController.hasRole(newController.FREEZER(), freezer), false);
        assertEq(newController.hasRole(newController.RELAYER(), relayer), false);

        assertEq(almProxy.hasRole(almProxy.CONTROLLER(), address(mainnetController)),     true);
        assertEq(rateLimits.hasRole(rateLimits.CONTROLLER(), address(mainnetController)), true);

        assertEq(almProxy.hasRole(almProxy.CONTROLLER(), address(newController)),     false);
        assertEq(rateLimits.hasRole(rateLimits.CONTROLLER(), address(newController)), false);

        vm.startPrank(SPARK_PROXY);
        wrapper.upgradeController(
            controllerInst,
            configAddresses,
            checkAddresses
        );

        assertEq(newController.hasRole(newController.FREEZER(), freezer), true);
        assertEq(newController.hasRole(newController.RELAYER(), relayer), true);

        assertEq(almProxy.hasRole(almProxy.CONTROLLER(), address(mainnetController)),     false);
        assertEq(rateLimits.hasRole(rateLimits.CONTROLLER(), address(mainnetController)), false);

        assertEq(almProxy.hasRole(almProxy.CONTROLLER(), address(newController)),     true);
        assertEq(rateLimits.hasRole(rateLimits.CONTROLLER(), address(newController)), true);
    }

}
