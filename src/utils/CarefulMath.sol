// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

/**
 * @title CarefulMath 
 * 
 * Multiplies and divides whole numbers with remainder using Chinese Remainder Theorem 
 * (CRT) - ideal for loss-safe financial math. 
 * 
 * @author John R. Kosinski
 * Zeppelin Finance 2023
 * All rights reserved. Unauthorized use prohibited.
 */
library CarefulMath {
    // Emitted when the ending result in `mulDiv` would overflow uint256.
    error PRBMath__MulDivOverflow(uint256 x, uint256 y, uint256 denominator);
    
    /**
     * Calculates floor(x*y÷denominator) with full precision.
     * 
     * @dev Credits to Remco Bloemen under // SPDX-License-Identifier: UNLICENSED license https://xn--2-umb.com/21/muldiv.
     * 
     * Requirements:
     *  - The denominator cannot be zero.
     *  - The result must fit within uint256.
     * 
     * Caveats:
     *  - This function does not work with fixed-point numbers.
     * 
     * @param x The multiplicand as an uint256.
     * @param y The multiplier as an uint256.
     * @param denominator The divisor as an uint256.
     * @return result The result as an uint256.
     */
    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        
        // 512-bit multiply [prod1 prod0] = x * y. Compute the product mod 2^256 and mod 2^256 - 1, then use
        // use the Chinese Remainder Theorem (CRT) to reconstruct the 512 bit result. The result is stored in two 256
        // variables such that product = prod1 * 2^256 + prod0.
        uint256 prod0; // Least significant 256 bits of the product
        uint256 prod1; // Most significant 256 bits of the product
        assembly {
            let mm := mulmod(x, y, not(0))
            prod0 := mul(x, y)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        // Handle non-overflow cases, 256 by 256 division.
        if (prod1 == 0) {
            unchecked {
                return prod0 / denominator;
            }
        }

        // Make sure the result is less than 2^256. Also prevents denominator == 0.
        if (prod1 >= denominator) {
            revert PRBMath__MulDivOverflow(x, y, denominator);
        }

        ///////////////////////////////////////////////
        // 512 by 256 division.
        ///////////////////////////////////////////////

        // Make division exact by subtracting the remainder from [prod1 prod0].
        uint256 remainder;
        assembly {
            // Compute remainder using the mulmod Yul instruction.
            remainder := mulmod(x, y, denominator)

            // Subtract 256 bit number from 512 bit number.
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        // Factor powers of two out of denominator and compute largest power of two divisor of denominator. Always >= 1.
        // See https://cs.stackexchange.com/q/138556/92363.
        unchecked {
            // Does not overflow because the denominator cannot be zero at this stage in the function.
            uint256 lpotdod = denominator & (~denominator + 1);
            assembly {
                // Divide denominator by lpotdod.
                denominator := div(denominator, lpotdod)

                // Divide [prod1 prod0] by lpotdod.
                prod0 := div(prod0, lpotdod)

                // Flip lpotdod such that it is 2^256 / lpotdod. If lpotdod is zero, then it becomes one.
                lpotdod := add(div(sub(0, lpotdod), lpotdod), 1)
            }

            // Shift in bits from prod1 into prod0.
            prod0 |= prod1 * lpotdod;

            // Invert denominator mod 2^256. Now that denominator is an odd number, it has an inverse modulo 2^256 such
            // that denominator * inv = 1 mod 2^256. Compute the inverse by starting with a seed that is correct for
            // four bits. That is, denominator * inv = 1 mod 2^4.
            uint256 inverse = (3 * denominator) ^ 2;

            // Use the Newton-Raphson iteration to improve the precision. Thanks to Hensel's lifting lemma, this also works
            // in modular arithmetic, doubling the correct bits in each step.
            inverse *= 2 - denominator * inverse; // inverse mod 2^8
            inverse *= 2 - denominator * inverse; // inverse mod 2^16
            inverse *= 2 - denominator * inverse; // inverse mod 2^32
            inverse *= 2 - denominator * inverse; // inverse mod 2^64
            inverse *= 2 - denominator * inverse; // inverse mod 2^128
            inverse *= 2 - denominator * inverse; // inverse mod 2^256

            // Because the division is now exact we can divide by multiplying with the modular inverse of denominator.
            // This will give us the correct result modulo 2^256. Since the preconditions guarantee that the outcome is
            // less than 2^256, this is the final result. We don't need to compute the high bits of the result and prod1
            // is no longer required.
            result = prod0 * inverse;
        }
    }
    
    function div(uint256 numerator, uint256 denominator) internal pure returns (uint256 result) {
        return mulDiv(numerator, 1, denominator);
    }

    // including this excludes from coverage report foundry
    function test() public {}
}