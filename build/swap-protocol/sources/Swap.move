module Swap::Swap {
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability};
    use std::string;
    use std::string::String;
    use std::option;
    use std::signer::address_of;
    use Swap::Math::{Self, sqrt, min};

    /// Error codes
    const ERR_PAIR_EXISTS: u64 = 1000;
    const ERR_PAIR_NOT_FOUND: u64 = 1001;
    const ERR_INSUFFICIENT_LIQUIDITY: u64 = 1002;
    const ERR_INSUFFICIENT_AMOUNT: u64 = 1003;

    /// Minimum liquidity constant
    const MINIMUM_LIQUIDITY: u64 = 1000;

    /// LP token struct
    struct LP<phantom X, phantom Y> {}

    /// Pair struct storing pool information
    struct Pair<phantom X, phantom Y> has key {
        x_coin: Coin<X>,
        y_coin: Coin<Y>,
        lp_locked: Coin<LP<X, Y>>,
        lp_mint: MintCapability<LP<X, Y>>,
        lp_burn: BurnCapability<LP<X, Y>>,
    }

    /// Generates LP token name and symbol
    public fun generate_lp_name_symbol<X, Y>(): String {
        let lp_name_symbol = string::utf8(b"");
        string::append_utf8(&mut lp_name_symbol, b"LP");
        string::append_utf8(&mut lp_name_symbol, b"-");
        string::append(&mut lp_name_symbol, coin::symbol<X>());
        string::append_utf8(&mut lp_name_symbol, b"-");
        string::append(&mut lp_name_symbol, coin::symbol<Y>());
        lp_name_symbol
    }

    /// Creates a new liquidity pool
    public entry fun create_pool<X, Y>(sender: &signer) {
        let sender_addr = address_of(sender);
        assert!(!pair_exist<X, Y>(sender_addr), ERR_PAIR_EXISTS);

        let lp_name_symbol = generate_lp_name_symbol<X, Y>();
        
        let (lp_burn, lp_freeze, lp_mint) = coin::initialize<LP<X, Y>>(
            sender,
            lp_name_symbol,
            lp_name_symbol,
            6,
            true,
        );

        coin::destroy_freeze_cap(lp_freeze);

        move_to(
            sender,
            Pair<X, Y> {
                x_coin: coin::zero<X>(),
                y_coin: coin::zero<Y>(),
                lp_locked: coin::zero<LP<X, Y>>(),
                lp_mint,
                lp_burn,
            },
        );
    }

    /// Adds liquidity to the pool
    public entry fun add_liquidity<X, Y>(
        sender: &signer,
        x_amount: u64,
        y_amount: u64
    ) acquires Pair {
        let sender_addr = address_of(sender);
        assert!(exists<Pair<X, Y>>(sender_addr), ERR_PAIR_NOT_FOUND);

        let pair = borrow_global_mut<Pair<X, Y>>(sender_addr);

        let x_amount = (x_amount as u128);
        let y_amount = (y_amount as u128);

        let x_reserve = (coin::value(&pair.x_coin) as u128);
        let y_reserve = (coin::value(&pair.y_coin) as u128);

        let y_amount_optimal = quote(x_amount, x_reserve, y_reserve);

        if (y_amount_optimal <= y_amount) {
            y_amount = y_amount_optimal;
        } else {
            let x_amount_optimal = quote(y_amount, y_reserve, x_reserve);
            x_amount = x_amount_optimal;
        };

        assert!(x_amount > 0 && y_amount > 0, ERR_INSUFFICIENT_AMOUNT);

        let x_amount_coin = coin::withdraw<X>(sender, (x_amount as u64));
        let y_amount_coin = coin::withdraw<Y>(sender, (y_amount as u64));

        coin::merge(&mut pair.x_coin, x_amount_coin);
        coin::merge(&mut pair.y_coin, y_amount_coin);

        let liquidity;
        let total_supply = *option::borrow(&coin::supply<LP<X, Y>>());
        
        if (total_supply == 0) {
            liquidity = sqrt(((x_amount * y_amount) as u128)) - MINIMUM_LIQUIDITY;
            let lp_locked = coin::mint(MINIMUM_LIQUIDITY, &pair.lp_mint);
            coin::merge(&mut pair.lp_locked, lp_locked);
        } else {
            liquidity = (min(
                Math::mul_div(x_amount, total_supply, x_reserve),
                Math::mul_div(y_amount, total_supply, y_reserve),
            ) as u64);
        };

        assert!(liquidity > 0, ERR_INSUFFICIENT_LIQUIDITY);

        let lp_coin = coin::mint<LP<X, Y>>(liquidity, &pair.lp_mint);
        let addr = address_of(sender);
        if (!coin::is_account_registered<LP<X, Y>>(addr)) {
            coin::register<LP<X, Y>>(sender);
        };
        coin::deposit(addr, lp_coin);
    }

    /// Removes liquidity from the pool
    public entry fun remove_liquidity<X, Y>(
        sender: &signer,
        liquidity: u64
    ) acquires Pair {
        let sender_addr = address_of(sender);
        assert!(exists<Pair<X, Y>>(sender_addr), ERR_PAIR_NOT_FOUND);
        assert!(liquidity > 0, ERR_INSUFFICIENT_LIQUIDITY);

        let pair = borrow_global_mut<Pair<X, Y>>(sender_addr);

        let liquidity_coin = coin::withdraw<LP<X, Y>>(sender, liquidity);
        coin::burn(liquidity_coin, &pair.lp_burn);

        let total_supply = *option::borrow(&coin::supply<LP<X, Y>>());
        let x_reserve = (coin::value(&pair.x_coin) as u128);
        let y_reserve = (coin::value(&pair.y_coin) as u128);

        let x_amount = Math::mul_div((liquidity as u128), x_reserve, total_supply);
        let y_amount = Math::mul_div((liquidity as u128), y_reserve, total_supply);

        let x_amount_coin = coin::extract<X>(&mut pair.x_coin, (x_amount as u64));
        let y_amount_coin = coin::extract<Y>(&mut pair.y_coin, (y_amount as u64));

        coin::deposit(address_of(sender), x_amount_coin);
        coin::deposit(address_of(sender), y_amount_coin);
    }

    /// Swaps token X for token Y
    public entry fun swap_x_to_y<X, Y>(
        sender: &signer,
        amount_in: u64
    ) acquires Pair {
        let sender_addr = address_of(sender);
        assert!(exists<Pair<X, Y>>(sender_addr), ERR_PAIR_NOT_FOUND);
        assert!(amount_in > 0, ERR_INSUFFICIENT_AMOUNT);

        let pair = borrow_global_mut<Pair<X, Y>>(sender_addr);

        let coin_in = coin::withdraw<X>(sender, amount_in);

        if (!coin::is_account_registered<Y>(address_of(sender))) {
            coin::register<Y>(sender);
        };

        let in_reserve = (coin::value(&pair.x_coin) as u128);
        let out_reserve = (coin::value(&pair.y_coin) as u128);

        let amount_out = get_amount_out((amount_in as u128), in_reserve, out_reserve);
        assert!((amount_out as u64) > 0, ERR_INSUFFICIENT_AMOUNT);

        coin::merge(&mut pair.x_coin, coin_in);
        let amount_out_coin = coin::extract(&mut pair.y_coin, (amount_out as u64));

        coin::deposit(address_of(sender), amount_out_coin);
    }

    /// Checks if a pair exists
    public fun pair_exist<X, Y>(addr: address): bool {
        exists<Pair<X, Y>>(addr) || exists<Pair<Y, X>>(addr)
    }

    /// Calculates the optimal token amount
    public fun quote(x_amount: u128, x_reserve: u128, y_reserve: u128): u128 {
        Math::mul_div(x_amount, y_reserve, x_reserve)
    }

    /// Calculates the output amount for a swap
    public fun get_amount_out(amount_in: u128, in_reserve: u128, out_reserve: u128): u128 {
        let amount_in_with_fee = amount_in * 997;
        let numerator = amount_in_with_fee * out_reserve;
        let denominator = in_reserve * 1000 + amount_in_with_fee;
        numerator / denominator
    }

    /// Gets the current reserves in the pool
    public fun get_coin<X, Y>(): (u64, u64) acquires Pair {
        let sender_addr = @Swap;
        assert!(exists<Pair<X, Y>>(sender_addr), ERR_PAIR_NOT_FOUND);
        
        let pair = borrow_global<Pair<X, Y>>(sender_addr);
        (coin::value(&pair.x_coin), coin::value(&pair.y_coin))
    }
}