module Swap::Math {
    /// Calculate the square root of a number using the Babylonian method
    public fun sqrt(y: u128): u64 {
        if (y < 4) {
            if (y == 0) {
                0u64
            } else {
                1u64
            }
        } else {
            let z = y;
            let x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            };
            (z as u64)
        }
    }

    /// Returns the minimum of two numbers
    public fun min(a: u128, b: u128): u128 {
        if (a < b) a else b
    }

    /// Performs multiplication followed by division, preventing overflow
    public fun mul_div(x: u128, y: u128, z: u128): u128 {
        // Prevent division by zero
        assert!(z > 0, 2001);
        
        // Handle overflow by performing division before multiplication when possible
        if (y <= 0xffffffffffffffffffffffffffffffff / x) {
            // No overflow in multiplication
            (x * y) / z
        } else {
            // Divide first to prevent overflow
            (x / z) * y + ((x % z) * y) / z
        }
    }
}