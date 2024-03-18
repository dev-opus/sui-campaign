#[allow(lint(self_transfer))]
module campaign::campaign {
  use std::vector;
  use sui::transfer;
  use sui::sui::SUI;
  use std::string::String;
  use sui::coin::{Self, Coin};
  use sui::clock::{Self, Clock};
  use sui::object::{Self, ID, UID};
  use sui::balance::{Self, Balance};
  use std::option::{Option, none, some};
  use sui::tx_context::{Self, TxContext};

  /* Error Constants */

  const ENotCampaignOwner: u64 = 0;
  const EInsufficientBalance: u64 = 1;
  const EMaxCampaignsReached: u64 = 2;
  const ECampaignEndedAlready: u64 = 3;
  const EDonationNotAllowed: u64 = 4;


  /* Structs */

  // admin capability struct
  struct AdminCap has key, store {
    id: UID
  }

  // campaign owner cap  struct
  struct CampaignOwnerCap has key, store{
    id: UID,
    campaign_id: ID
  }


  struct OwnerAddressVector has key, store {
    id: UID,
    addresses: vector<address>
  }

  struct Campaign has key, store {
    id: UID,
    title: String,
    about: String, // a breif description of the campaign
    ended: bool,
    creator: address,
    received: Balance<SUI>,
    donations: vector<DonationReceipt>,
    started_at: u64,
    ended_at: Option<u64>
  }

  struct CampaignDetails has copy, drop{
    ended: bool,
    started_at: u64,
    amount_donated: u64,
    num_of_donations: u64,
    campaign_title: String,
    campaign_about: String,
  }

  struct Donation has key, store {
    id: UID,
    donor: address,
    campaign: ID,
    amount_donated: u64,
    donated_at: u64
  }

  struct DonationReceipt has key, store {
    id: UID,
    donation_id: ID
  }

  struct Withdrawal has key, store {
    id: UID,
    campaign_id: ID,
    amount_withdrawn: u64,
    withdrawn_at: u64
  }

  /* Functions */

  // creates an admin account on initialization (only one of such accounts)
  // creates a vector for storing campaign owner addresses
  fun init (ctx: &mut TxContext) {
    let admin = AdminCap {
      id: object::new(ctx)
    };

   let addresses = vector::empty<address>();
   let admin_address = tx_context::sender(ctx);

    let owner_address_vector = OwnerAddressVector {
      id: object::new(ctx),
      addresses,
    };

    transfer::share_object(owner_address_vector);
    transfer::transfer(admin, admin_address);
  }  

  // create a campaign (and the owner object)
  public entry fun create_campaign(
    title: String,
    about: String,
    clock: &Clock,
    address_vector: &mut OwnerAddressVector,
    ctx: &mut TxContext
    ) {
    let campaign_owner_address = tx_context::sender(ctx);
    assert!(!vector::contains<address>(&address_vector.addresses, &campaign_owner_address), EMaxCampaignsReached);

    let campaign_uid = object::new(ctx);
    let campaign_id = object::uid_to_inner(&campaign_uid);

    let campaign = Campaign {
      id: campaign_uid,
      title,
      about,
      ended: false,
      received: balance::zero(),
      creator: campaign_owner_address,
      donations: vector::empty<DonationReceipt>(),
      started_at: clock::timestamp_ms(clock),
      ended_at: none()
    };

    let campaign_owner_id = object::new(ctx);

    let campaign_owner = CampaignOwnerCap {
      id: campaign_owner_id,
      campaign_id
    };

    vector::push_back<address>(&mut address_vector.addresses, campaign_owner_address);

    transfer::share_object(campaign);
    transfer::transfer(campaign_owner, campaign_owner_address);
  }

  // donate to a campaign
  public entry fun donate_to_campaign(amount: Coin<SUI>, campaign: &mut Campaign, clock: &Clock, ctx: &mut TxContext) {

    // asserts that the campaign is still ongoing before attempting to donate
    assert!(campaign.ended == false, ECampaignEndedAlready);
    assert!(campaign.creator != tx_context::sender(ctx), EDonationNotAllowed);

    let amount_donated = coin::value(&amount);
    let donor_address = tx_context::sender(ctx);

    let coin_balance = coin::into_balance(amount);
    balance::join(&mut campaign.received, coin_balance);

    let donation_uid = object::new(ctx);
    let donation_id = object::uid_to_inner(&donation_uid);

    let donation = Donation {
      id: donation_uid,
      amount_donated,
      donor: donor_address,
      campaign: object::uid_to_inner(&campaign.id),
      donated_at: clock::timestamp_ms(clock)
    };

    let donation_receipt = DonationReceipt {
      id: object::new(ctx),
      donation_id
    };

    vector::push_back(&mut campaign.donations, donation_receipt);
    transfer::share_object(donation);
  }


  // withdraw from a campaign 
  public entry fun withdraw(
   cap: &CampaignOwnerCap,
   amount: u64,
   campaign: &mut Campaign,
   clock: &Clock, 
   ctx: &mut TxContext
   ) {
    // asserts that the campaign to be withdrawn from actually belongs to the caller
    assert!(cap.campaign_id == object::uid_to_inner(&campaign.id), ENotCampaignOwner);
    let campaign_balance = balance::value(&campaign.received);

    // asserts that the campaign values is at least equal to the amount
    // being withdrawn to avoid attempting excessive withdrawals
    assert!(campaign_balance >= amount, EInsufficientBalance);
    let withdrawn = coin::take(&mut campaign.received, amount, ctx);

    let withdrawal = Withdrawal {
      id: object::new(ctx),
      campaign_id: object::uid_to_inner(&campaign.id),
      amount_withdrawn: amount,
      withdrawn_at: clock::timestamp_ms(clock)
    };

    transfer::public_transfer(withdrawn, campaign.creator);
    transfer::transfer(withdrawal, campaign.creator);
  }

  // end campaign
  // this function uses the capability design pattern (admin_cap) to ensure that only
  // an admin can end campaigns
  public entry fun end_campaign(_: &AdminCap, campaign: &mut Campaign, clock: &Clock) {

    // asserts that the campaign isn' ended already before attempting to end it
    assert!(campaign.ended == false, ECampaignEndedAlready);
    campaign.ended = true;
    campaign.ended_at = some(clock::timestamp_ms(clock));
  }

  // get campaign details
  public entry fun get_campaign_details(campaign: &Campaign): CampaignDetails {
    let campaign_details = CampaignDetails {
      ended: campaign.ended,
      campaign_title: campaign.title,
      campaign_about: campaign.about,
      started_at: campaign.started_at,
      amount_donated: balance::value(&campaign.received),
      num_of_donations: vector::length<DonationReceipt>(&campaign.donations),
    };

    campaign_details
  }
}
