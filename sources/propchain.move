module propchain::real_estate {
    use sui::coin::{coin, Self};
    use sui::SUI;
    use sui::tx_context::{TxContext, sender};
    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID};
    use sui::transfer::{Self};
    use sui::event;
    use std::vector;

    // Import structs from PropertyModule
    use PropertyModule::{Property, Transaction, RentalAgreement};

    // Error Codes
    const INSUFFICIENT_FUNDS: u64 = 1;
    const TRANSACTION_NOT_VERIFIED: u64 = 2;
    const PROPERTY_NOT_AVAILABLE: u64 = 3;
    const ONLY_OWNER_CAN_MANAGE: u64 = 4;
    const UNAUTHORIZED_ACCESS: u64 = 5;
    const VERIFICATION_FAILED: u64 = 6;
    const AGREEMENT_NOT_ACTIVE: u64 = 7;
    const ESCROW_FUNDS_LOCKED: u64 = 8;
    
    // Lease Terminated Event
    struct LeaseTerminated has key, store {
        agreement_id: UID,
        terminated_by: address,
        termination_reason: vector<u8>,
        is_successful: bool,
    }

    // Struct for dynamic pricing factors
struct PricingFactor has key, store {
    demand: u64,  // Represents demand score, influencing price
    base_price: u64,
}

// Function to calculate dynamic price based on demand
public fun calculate_dynamic_price(
    pricing_factor: &PricingFactor, 
    demand_threshold: u64, 
    multiplier: u64
): u64 {
    if pricing_factor.demand > demand_threshold {
        pricing_factor.base_price * multiplier  // Increase price
    } else {
        pricing_factor.base_price // Use base price
    }
}

// Function to list a property with dynamic pricing
public fun list_property_with_dynamic_pricing(
    property: &mut Property, 
    pricing_factor: &PricingFactor, 
    ctx: &mut TxContext
) {
    assert!(sender(ctx) == property.owner, ONLY_OWNER_CAN_MANAGE);
    
    let dynamic_price = calculate_dynamic_price(pricing_factor, 100, 2);  // Adjust price if demand is above threshold
    property.is_for_sale = true;
    property.price = dynamic_price;
}


    // Function to create a new rental agreement
    public fun create_rental_agreement(
        property_id: UID, 
        tenant: address, 
        rent_amount: u64, 
        due_date: u64, 
        ctx: &mut TxContext
    ) {
        let agreement = RentalAgreement {
            id: object::new_uid(ctx),
            property_id,
            tenant,
            owner: sender(ctx),
            rent_amount,
            due_date,
            is_active: true,
        };

        // Emit an event or store the agreement
        event::emit(agreement);
    }

    // Function to terminate rental agreement (owner or tenant)
    public fun terminate_rental_agreement(
        agreement: &mut RentalAgreement, 
        termination_reason: vector<u8>, 
        ctx: &mut TxContext
    ) {
        assert!(sender(ctx) == agreement.owner || sender(ctx) == agreement.tenant, UNAUTHORIZED_ACCESS);
        agreement.is_active = false;

        let event = LeaseTerminated {
            agreement_id: agreement.id,
            terminated_by: sender(ctx),
            termination_reason,
            is_successful: true,
        };
        event::emit(event);
    }

    // Function to list a property for sale
    public fun list_property_for_sale(
        property: &mut Property, 
        price: u64, 
        ctx: &mut TxContext
    ) {
        assert!(sender(ctx) == property.owner, ONLY_OWNER_CAN_MANAGE);
        property.is_for_sale = true;
        property.price = price;
    }

    // Function to track property ownership history
    public struct OwnershipHistory has key, store {
        property_id: UID,
        owner_history: vector<address>,
    }

    public fun transfer_property(
        property: &mut Property, 
        new_owner: address, 
        history: &mut OwnershipHistory, 
        ctx: &mut TxContext
    ) {
        assert!(sender(ctx) == property.owner, UNAUTHORIZED_ACCESS);
        vector::push_back(&mut history.owner_history, property.owner);
        transfer::public_transfer(property, new_owner);
    }

    // Function to complete a transaction with multi-party verification
    public fun complete_transaction(
        transaction: &mut Transaction, 
        verifier: address, 
        ctx: &mut TxContext
    ) {
        assert!(vector::contains(&transaction.verifiers, verifier), UNAUTHORIZED_ACCESS);
        transaction.is_verified = true;

        if transaction.is_verified && transaction.is_completed == false {
            transaction.is_completed = true;
            event::emit(transaction);
        }
    }

    // Add escrow management for handling transactions securely
    struct Escrow has key, store {
        id: UID,
        amount: Balance<SUI>,
        buyer: address,
        seller: address,
        is_locked: bool,
    }

    public fun initiate_escrow(
        property: &Property, 
        buyer: address, 
        seller: address, 
        amount: u64, 
        ctx: &mut TxContext
    ) {
        let escrow = Escrow {
            id: object::new_uid(ctx),
            amount: coin::split(coin::zero<SUI>(), amount),
            buyer,
            seller,
            is_locked: true,
        };

        event::emit(escrow);
    }

    public fun release_escrow(
        escrow: &mut Escrow, 
        recipient: address, 
        ctx: &mut TxContext
    ) {
        assert!(escrow.is_locked, ESCROW_FUNDS_LOCKED);
        escrow.is_locked = false;
        transfer::public_transfer(&mut escrow.amount, recipient);
    }

    // Function to calculate discount based on reputation score
public fun calculate_discount(reputation: &Reputation): u64 {
    if reputation.score > 80 {
        10  // 10% discount for high reputation scores
    } else {
        0   // No discount
    }
}

// Function to apply discount to rent payment
public fun apply_rent_discount(
    agreement: &mut RentalAgreement, 
    reputation: &Reputation, 
    ctx: &mut TxContext
) {
    let discount_percentage = calculate_discount(reputation);
    let discount_amount = agreement.rent_amount * discount_percentage / 100;

    agreement.rent_amount = agreement.rent_amount - discount_amount;

    // Emit an event to track the discounted rent amount
    event::emit(agreement);
}

// Function to apply penalty for late rent payment
public fun apply_late_payment_penalty(
    agreement: &mut RentalAgreement, 
    current_date: u64, 
    ctx: &mut TxContext
) {
    if current_date > agreement.due_date {
        let penalty_amount = agreement.rent_amount * 10 / 100;  // 10% penalty
        agreement.rent_amount = agreement.rent_amount + penalty_amount;
        
        // Emit an event to track the penalty
        event::emit(agreement);
    }
}

// Function to renew a rental agreement
public fun renew_lease(
    agreement: &mut RentalAgreement, 
    new_due_date: u64, 
    new_rent_amount: u64, 
    ctx: &mut TxContext
) {
    assert!(sender(ctx) == agreement.owner || sender(ctx) == agreement.tenant, UNAUTHORIZED_ACCESS);
    assert!(agreement.is_active, AGREEMENT_NOT_ACTIVE);

    agreement.due_date = new_due_date;
    agreement.rent_amount = new_rent_amount;
    agreement.is_active = true;

    // Emit an event for the lease renewal
    event::emit(agreement);
}
}
