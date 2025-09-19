// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/* ───────── External deps (raw URLs for Remix) ───────── */
// OpenZeppelin 4.9.6
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.6/contracts/access/Ownable2Step.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.6/contracts/security/ReentrancyGuard.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.6/contracts/security/Pausable.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.6/contracts/token/ERC20/IERC20.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.6/contracts/token/ERC20/utils/SafeERC20.sol";

// PRBMath 4.0.2 (UD60x18 fixed-point)
import { UD60x18, ud, unwrap } from "https://raw.githubusercontent.com/PaulRBerg/prb-math/v4.0.2/src/UD60x18.sol";
import { exp, pow } from "https://raw.githubusercontent.com/PaulRBerg/prb-math/v4.0.2/src/ud60x18/Math.sol";

/**
 * @title DPMC – Dynamic Price Modeling Concept (on-rails sale)
 *
 * x = tokensSold / saleSupply  (progress ∈ [0,1])
 * p(x) = P0 + (P1-P0) * (1 - exp(-Kx))
 * r(x) = R0 * (1 - x^ALPHA)            // reward mirror (sqrt when ALPHA=0.5e18)
 * ETH = saleSupply * ( I(x1) - I(x0) ) // where I(x)=∫ p(u)du = P0x + (P1-P0)*( x - (1 - exp(-Kx))/K )
 *
 * Rails: splits native to Fund + Shareholding (+ optional referrer), remainder pays the curve integral.
 * Governance: Ownable2Step; lockParams() freezes economics. Hand ownership to DAO timelock.
 */
contract DPMC is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* ───────── Sale state ───────── */
    IERC20  public immutable token;        // ERC20 being sold
    uint256 public immutable saleSupply;   // total tokens allocated to DPMC (1e18 units)
    uint256 public tokensSold;             // 1e18 units sold

    // Curve params (UD60x18: 1e18 = 1.0)
    UD60x18 public P0;       // initial price (wei per token)
    UD60x18 public P1;       // target price  (wei per token)
    UD60x18 public K;        // steepness (e.g., 0.05e18)
    UD60x18 public R0;       // initial reward multiplier (e.g., 0.50e18)
    UD60x18 public ALPHA;    // reward power (e.g., 0.5e18 for sqrt mirror)

    bool public paramsLocked;

    /* ───────── Rails / fees ───────── */
    address public fundTreasury;           // DAO/Fund receiver (native)
    address public shareholdingTreasury;   // Global Shareholding receiver (native)
    uint16  public fundBps  = 300;         // 3.00%
    uint16  public shareBps = 200;         // 2.00%
    uint16  public referrerBps = 0;        // optional referral cut
    uint16  public constant BPS_DENOM = 10_000;

    /* ───────── Events ───────── */
    event Purchased(address indexed buyer, uint256 ethUsed, uint256 tokensOut, uint256 rewardOut, uint256 newSold);
    event ParamsLocked();
    event RailsUpdated(address fund, address share, uint16 fundBps, uint16 shareBps, uint16 refBps);
    event CurveUpdated(uint256 P0, uint256 P1, uint256 K, uint256 R0, uint256 ALPHA);

    /* ───────── Constructor ───────── */
    constructor(
        address _token,
        uint256 _saleSupply,              // 1e18 token units
        uint256 _P0_weiPerToken,
        uint256 _P1_weiPerToken,
        uint256 _K_ud,
        uint256 _R0_ud,
        uint256 _ALPHA_ud,
        address _fund,
        address _share
    ) {
        require(_token != address(0) && _fund != address(0) && _share != address(0), "zero addr");
        require(_saleSupply > 0, "supply=0");
        require(_P1_weiPerToken > _P0_weiPerToken, "P1>P0");

        token = IERC20(_token);
        saleSupply = _saleSupply;

        P0 = ud(_P0_weiPerToken);
        P1 = ud(_P1_weiPerToken);
        K  = ud(_K_ud);
        R0 = ud(_R0_ud);
        ALPHA = ud(_ALPHA_ud);

        fundTreasury = _fund;
        shareholdingTreasury = _share;
    }

    /* ───────── Public buying (ETH → tokens) ───────── */
    receive() external payable { _buy(address(0)); }
    function buy() external payable { _buy(address(0)); }
    function buyWithRef(address ref) external payable { _buy(ref); }

    function _buy(address referrer) internal whenNotPaused nonReentrant {
        require(tokensSold < saleSupply, "sold out");
        require(msg.value > 0, "ETH=0");

        // Split native to rails first
        uint256 fundCut  = (msg.value * fundBps)  / BPS_DENOM;
        uint256 shareCut = (msg.value * shareBps) / BPS_DENOM;
        uint256 refCut   = (referrer != address(0) && referrerBps > 0) ? (msg.value * referrerBps) / BPS_DENOM : 0;
        uint256 usable   = msg.value - fundCut - shareCut - refCut;

        if (fundCut  > 0) _safeSend(fundTreasury, fundCut);
        if (shareCut > 0) _safeSend(shareholdingTreasury, shareCut);
        if (refCut   > 0) _safeSend(referrer, refCut);

        // Solve for x1 from integral equality
        UD60x18 S  = ud(saleSupply);
        UD60x18 x0 = ud(tokensSold).div(S);
        UD60x18 targetEth = ud(usable);

        UD60x18 x1 = _solveX1(x0, targetEth, S);        // x1 ∈ [x0,1]

        // Exact ETH used, and token delta
        UD60x18 ethExact = S.mul(_I(x1).sub(_I(x0)));
        uint256 deltaT = unwrap(x1.mul(S)) - tokensSold; // tokensOut (1e18)
        require(deltaT > 0, "tiny");
        require(tokensSold + deltaT <= saleSupply, "cap");

        // Reward mirror (post-purchase progress). Rename local var to avoid name clash with function.
        UD60x18 rf = _reward(x1);                        // 0..R0
        uint256 rewardOut = (deltaT * unwrap(rf)) / 1e18;

        tokensSold += deltaT;
        token.safeTransfer(msg.sender, deltaT);
        if (rewardOut > 0) token.safeTransfer(msg.sender, rewardOut);

        // Refund dust (if integral < usable by a few wei)
        uint256 spent = fundCut + shareCut + refCut + unwrap(ethExact);
        if (msg.value > spent) _safeSend(msg.sender, msg.value - spent);

        emit Purchased(msg.sender, unwrap(ethExact), deltaT, rewardOut, tokensSold);
    }

    /* ───────── Curves ───────── */

    // View helper: price p(x) for a given x in UD60x18 (1e18 = 1.0)
    function price(uint256 x_ud) external view returns (uint256) {
        return unwrap(_p(ud(x_ud)));
    }

    // View helper: reward factor r(x) for a given x in UD60x18
    function rewardFactor(uint256 x_ud) external view returns (uint256) {
        return unwrap(_reward(ud(x_ud)));
    }

    // Integral I(x) = P0*x + (P1-P0)*( x - (1 - exp(-Kx))/K )
    function _I(UD60x18 x) internal view returns (UD60x18) {
        UD60x18 d = P1.sub(P0);
        // exp(-Kx) = 1 / exp(Kx)
        UD60x18 expPos = exp(K.mul(x));
        UD60x18 expNeg = ud(1e18).div(expPos);
        UD60x18 oneMinusExp = ud(1e18).sub(expNeg);
        UD60x18 part = x.sub(oneMinusExp.div(K));
        return P0.mul(x).add(d.mul(part));
    }

    // p(x) = P0 + (P1-P0)*(1 - exp(-Kx))
    function _p(UD60x18 x) internal view returns (UD60x18) {
        UD60x18 expPos = exp(K.mul(x));
        UD60x18 expNeg = ud(1e18).div(expPos);
        UD60x18 oneMinusExp = ud(1e18).sub(expNeg);
        return P0.add(P1.sub(P0).mul(oneMinusExp));
    }

    // r(x) = R0 * (1 - x^ALPHA)
    function _reward(UD60x18 x) internal view returns (UD60x18) {
        if (unwrap(x) >= 1e18) return ud(0);
        UD60x18 xPow = pow(x, ALPHA);
        return R0.mul(ud(1e18).sub(xPow));
    }

    // Binary search for x1: S*(I(x1)-I(x0)) ≈ targetEth
    function _solveX1(UD60x18 x0, UD60x18 targetEth, UD60x18 S) internal view returns (UD60x18) {
        UD60x18 lo = x0;
        UD60x18 hi = ud(1e18);
        UD60x18 target = targetEth.div(S);

        for (uint256 i = 0; i < 60; i++) {
            UD60x18 mid = lo.add(hi).div(ud(2e18));
            UD60x18 diff = _I(mid).sub(_I(x0));
            if (unwrap(diff) >= unwrap(target)) {
                hi = mid;
            } else {
                lo = mid;
            }
        }
        return hi;
    }

    /* ───────── Governance / Admin ───────── */
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function lockParams() external onlyOwner {
        paramsLocked = true;
        emit ParamsLocked();
    }

    function updateRails(
        address _fund, address _share,
        uint16 _fundBps, uint16 _shareBps, uint16 _refBps
    ) external onlyOwner {
        require(_fund != address(0) && _share != address(0), "zero");
        require(_fundBps + _shareBps + _refBps <= BPS_DENOM, "bps>100%");
        fundTreasury = _fund;
        shareholdingTreasury = _share;
        fundBps = _fundBps;
        shareBps = _shareBps;
        referrerBps = _refBps;
        emit RailsUpdated(_fund, _share, _fundBps, _shareBps, _refBps);
    }

    // Curve can be tweaked until locked (use DAO timelock as owner)
    function updateCurve(
        uint256 _P0, uint256 _P1, uint256 _K, uint256 _R0, uint256 _ALPHA
    ) external onlyOwner {
        require(!paramsLocked, "locked");
        require(_P1 > _P0, "P1>P0");
        P0 = ud(_P0); P1 = ud(_P1); K = ud(_K); R0 = ud(_R0); ALPHA = ud(_ALPHA);
        emit CurveUpdated(_P0,_P1,_K,_R0,_ALPHA);
    }

    // Rescue (non-sale) ERC20 & native
    function rescueERC20(address erc20, uint256 amount) external onlyOwner {
        require(erc20 != address(token), "sale token");
        IERC20(erc20).safeTransfer(owner(), amount);
    }
    function rescueETH(uint256 amount) external onlyOwner {
        (bool ok,) = owner().call{value: amount}("");
        require(ok, "send fail");
    }

    /* ───────── Utils ───────── */
    function _safeSend(address to, uint256 amt) internal {
        (bool ok,) = to.call{value: amt}("");
        require(ok, "native send fail");
    }
}
