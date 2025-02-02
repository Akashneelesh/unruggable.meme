//! `UnruggableMemecoin` is an ERC20 token has additional features to prevent rug pulls.
use starknet::ContractAddress;

#[starknet::contract]
mod UnruggableMemecoin {
    use core::array::ArrayTrait;
    use integer::BoundedInt;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::access::ownable::ownable::OwnableComponent::InternalTrait;
    use openzeppelin::token::erc20::ERC20Component;
    use starknet::{ContractAddress, get_caller_address};
    use unruggable::tokens::interface::{
        IUnruggableMemecoinSnake, IUnruggableMemecoinCamel, IUnruggableAdditional
    };
    use zeroable::Zeroable;
    use alexandria_merkle_tree::merkle_tree::{
        Hasher, MerkleTree, pedersen::PedersenHasherImpl, MerkleTreeTrait, MerkleTreeImpl
    };
    use openzeppelin::security::initializable::InitializableComponent::InternalTrait as InitializableTrait;
    use openzeppelin::security::initializable::InitializableComponent;

    // Components.
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    component!(path: InitializableComponent, storage: initializable, event: InitializableEvent);
    // Internals
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    // ERC20 entrypoints.
    #[abi(embed_v0)]
    impl ERC20MetadataImpl = ERC20Component::ERC20MetadataImpl<ContractState>;

    // Constants.
    /// The maximum number of holders allowed before launch.
    /// This is to prevent the contract from being launched with a large number of holders.
    /// Once reached, transfers are disabled until the memecoin is launched.
    const MAX_HOLDERS_BEFORE_LAUNCH: u8 = 10;
    /// The maximum percentage of the total supply that can be allocated to the team.
    /// This is to prevent the team from having too much control over the supply.
    const MAX_SUPPLY_PERCENTAGE_TEAM_ALLOCATION: u8 = 10;
    /// The maximum percentage of the supply that can be bought at once.
    const MAX_PERCENTAGE_BUY_LAUNCH: u8 = 2;

    #[storage]
    struct Storage {
        marker_v_0: (),
        launched: bool,
        pre_launch_holders_count: u8,
        // Components.
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        initializable: InitializableComponent::Storage,
        //Contract Storage
        merkle_root: felt252,
        has_claimed: LegacyMap::<ContractAddress, bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        InitializableEvent: InitializableComponent::Event,
        //Contract Events
        ClaimedAirdrop: ClaimedAirdrop,
    }

    mod Errors {
        const MAX_HOLDERS_REACHED: felt252 = 'Unruggable: max holders reached';
        const ARRAYS_LEN_DIF: felt252 = 'Unruggable: arrays len dif';
    }

    #[derive(Drop, starknet::Event)]
    struct ClaimedAirdrop {
        account: ContractAddress,
        amount: u256
    }


    /// Constructor called once when the contract is deployed.
    /// # Arguments
    /// * `owner` - The owner of the contract.
    /// * `initial_recipient` - The initial recipient of the initial supply.
    /// * `name` - The name of the token.
    /// * `symbol` - The symbol of the token.
    /// * `initial_supply` - The initial supply of the token.
    /// * `initial_holders` - The initial holders of the token, an array of holder_address
    /// * `initial_holders_amounts` - The initial amounts of tokens minted to the initial holders, an array of amounts   
    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        initial_recipient: ContractAddress,
        name: felt252,
        symbol: felt252,
        initial_supply: u256,
        initial_holders: Span<ContractAddress>,
        initial_holders_amounts: Span<u256>,
    ) {
        // Initialize the ERC20 token.
        self.erc20.initializer(name, symbol);

        // Initialize the owner.
        self.ownable.initializer(owner);

        assert(initial_holders.len() == initial_holders_amounts.len(), Errors::ARRAYS_LEN_DIF);
        assert(
            initial_holders.len() <= MAX_HOLDERS_BEFORE_LAUNCH.into(), Errors::MAX_HOLDERS_REACHED
        );

        // Initialize the token / internal logic
        self
            ._initializer(
                owner,
                initial_recipient,
                name,
                symbol,
                initial_supply,
                initial_holders,
                initial_holders_amounts
            );
    }

    //
    // External
    //
    #[abi(embed_v0)]
    impl UnruggableEntrypoints of IUnruggableAdditional<ContractState> {
        // ************************************
        // * UnruggableMemecoin functions
        // ************************************

        fn launched(self: @ContractState) -> bool {
            self.launched.read()
        }

        fn launch_memecoin(ref self: ContractState) {
            // Checks: Only the owner can launch the memecoin.
            self.ownable.assert_only_owner();
            // Effects.

            // Launch the coin
            self.launched.write(true);
        // Interactions.
        }

        /// Returns the team allocation in tokens.
        fn get_team_allocation(self: @ContractState) -> u256 {
            self.erc20.ERC20_total_supply.read()
                * MAX_SUPPLY_PERCENTAGE_TEAM_ALLOCATION.into()
                / 100
        }

        /// Sets the Merkle root for the contract.
        /// This function updates the Merkle root stored in the contract's state.
        /// It is essential for maintaining the integrity of the Merkle tree used in various contract functionalities.
        
        /// # Arguments
        /// * `merkle_root` - The new Merkle root to be set, represented as a `felt252`.

        fn set_merkle_root(ref self: ContractState, merkle_root: felt252) {
            self.ownable.assert_only_owner();
            self.initializable.initialize();
            self.merkle_root.write(merkle_root);
        }

        /// Retrieves the current Merkle root from the contract.
        /// This function allows the contract owner to obtain the current Merkle root stored in the contract's state.
        /// The Merkle root is crucial for verifying proofs in various contract operations.

        /// # Returns
        /// * `felt252` - The current Merkle root stored in the contract.

        fn get_merkle_root(self: @ContractState) -> felt252 {
            //Getting the merkle root
            self.ownable.assert_only_owner();
            self.merkle_root.read()
        }

        /// Claims an airdrop for a specific account.
        /// This function is part of the contract's state and is used to claim airdrops for accounts.
        /// It involves a Merkle tree verification process to ensure the legitimacy of the claim.

        /// # Arguments
        /// * `to` - The address of the contract for which the airdrop is being claimed.
        /// * `amount` - The amount of tokens to be airdropped, represented as a `u256`.
        /// * `leaf` - A mutable leaf node in the Merkle tree, represented as a `felt252`.
        /// * `proof` - A mutable span of `felt252` elements representing the Merkle proof.
        fn claim_airdrop(
            ref self: ContractState,
            to: ContractAddress,
            amount: u256,
            mut leaf: felt252,
            mut proof: Span<felt252>,
        ) {
            //Initializing the Merkletree
            let mut merkle_tree: MerkleTree<Hasher> = MerkleTreeTrait::new();
            //Pedersen Hashing of the ContractAddress and Amount
            let to_felt252: felt252 = starknet::contract_address_to_felt252(to);
            let amount_felt252: felt252 = amount.try_into().unwrap();
            let hashed_value: felt252 = pedersen::pedersen(to_felt252, amount_felt252);

            //Verifying if the leaf and hashed value are equal
            assert(hashed_value == leaf, 'Invalid leaf');

            //Verifying the proof
            let valid_proof: bool = merkle_tree.verify(self.merkle_root.read(), leaf, proof);
            assert(self.has_claimed.read(to) == false, 'Already Claimed');
            assert(valid_proof == true, 'Invalid proof');

            //Changing the has_claimed state to true
            self.has_claimed.write(to, true);

            //Minting the tokens
            self.erc20._mint(to, amount);
            //Emitting an event of ClaimedAirdrop
            self.emit(ClaimedAirdrop { account: to, amount: amount });
        }
    }

    #[abi(embed_v0)]
    impl SnakeEntrypoints of IUnruggableMemecoinSnake<ContractState> {
        // ************************************
        // * snake_case functions
        // ************************************
        fn total_supply(self: @ContractState) -> u256 {
            self.erc20.ERC20_total_supply.read()
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.erc20.ERC20_balances.read(account)
        }

        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress
        ) -> u256 {
            self.erc20.ERC20_allowances.read((owner, spender))
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            self._check_max_buy_percentage(amount);
            let sender = get_caller_address();
            self._transfer(sender, recipient, amount);
            true
        }

        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            let caller = get_caller_address();
            self._check_max_buy_percentage(amount);
            self.erc20._spend_allowance(sender, caller, amount);
            self.erc20._transfer(sender, recipient, amount);
            true
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();
            self.erc20._approve(caller, spender, amount);
            true
        }
    }

    #[abi(embed_v0)]
    impl CamelEntrypoints of IUnruggableMemecoinCamel<ContractState> {
        fn totalSupply(self: @ContractState) -> u256 {
            self.erc20.ERC20_total_supply.read()
        }
        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            self.erc20.ERC20_balances.read(account)
        }
        fn transferFrom(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            let caller = get_caller_address();
            self.erc20._spend_allowance(sender, caller, amount);
            self._transfer(sender, recipient, amount);
            true
        }
    }


    //
    // Internal
    //
    #[generate_trait]
    impl UnruggableMemecoinInternalImpl of UnruggableMemecoinInternalTrait {
        /// Internal function to enforce pre launch holder limit
        ///
        /// Note that when transfers are done, between addresses that already
        /// hold tokens, we do not increment the number of holders. it only
        /// gets incremented when the recipient that hold no tokens
        ///
        /// # Arguments
        /// * `recipient` - The recipient of the tokens being transferred.
        #[inline(always)]
        fn _enforce_holders_limit(ref self: ContractState, recipient: ContractAddress) {
            // enforce max number of holders before launch

            if !self.launched.read() && self.balance_of(recipient) == 0 {
                let current_holders_count = self.pre_launch_holders_count.read();
                assert(
                    current_holders_count < MAX_HOLDERS_BEFORE_LAUNCH, Errors::MAX_HOLDERS_REACHED
                );

                self.pre_launch_holders_count.write(current_holders_count + 1);
            }
        }


        /// Internal function to mint tokens
        ///
        /// Before minting, a check is done to ensure that 
        /// only `MAX_HOLDERS_BEFORE_LAUNCH` addresses can hold 
        /// tokens if token hasn't launched 
        ///
        /// # Arguments
        /// * `recipient` - The recipient of the tokens.
        /// * `amount` - The amount of tokens to be minted.
        fn _mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            self._enforce_holders_limit(recipient);
            self.erc20._mint(recipient, amount);
        }

        /// Internal function to transfer tokens
        ///
        /// Before transferring, a check is done to ensure that 
        /// only `MAX_HOLDERS_BEFORE_LAUNCH` addresses can hold 
        /// tokens if token hasn't launched 
        ///
        /// # Arguments
        /// * `sender` - The sender or owner of the tokens.
        /// * `recipient` - The recipient of the tokens.
        /// * `amount` - The amount of tokens to be transferred.
        fn _transfer(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {
            self._enforce_holders_limit(recipient);
            self.erc20._transfer(sender, recipient, amount);
        }

        fn _check_max_buy_percentage(self: @ContractState, amount: u256) {
            assert(
                self.erc20.ERC20_total_supply.read()
                    * MAX_PERCENTAGE_BUY_LAUNCH.into()
                    / 100 >= amount,
                'Max buy cap reached'
            )
        }

        /// Constructor logic.
        /// # Arguments
        /// * `owner` - The owner of the contract.
        /// * `owner` - The owner of the contract.
        /// * `initial_recipient` - The initial recipient of the initial supply.
        /// * `name` - The name of the token.
        /// * `symbol` - The symbol of the token.
        /// * `initial_supply` - The initial supply of the token.
        /// * `initial_holders` - The initial holders of the token, an array of holder_address
        /// * `initial_holders_amounts` - The initial amounts of tokens minted to the initial holders, an array of amounts        
        fn _initializer(
            ref self: ContractState,
            owner: ContractAddress,
            initial_recipient: ContractAddress,
            name: felt252,
            symbol: felt252,
            initial_supply: u256,
            initial_holders: Span<ContractAddress>,
            initial_holders_amounts: Span<u256>
        ) {
            let mut initial_minted_supply: u256 = 0;
            let mut team_allocation: u256 = 0;
            let mut i: usize = 0;
            loop {
                if i >= initial_holders.len() {
                    break;
                }
                let address = *initial_holders.at(i);
                let amount = *initial_holders_amounts.at(i);
                initial_minted_supply += amount;
                if (i == 0) {
                    assert(address == initial_recipient, 'initial recipient mismatch');
                    // NO HOLDING LIMIT HERE. IT IS THE ACCOUNT THAT WILL LAUNCH THE LIQUIDITY POOL
                    self.erc20._mint(address, amount);
                } else {
                    team_allocation += amount;
                    let max_alloc = initial_supply
                        * MAX_SUPPLY_PERCENTAGE_TEAM_ALLOCATION.into()
                        / 100;
                    assert(team_allocation <= max_alloc, 'Unruggable: max team allocation');
                    self.erc20._mint(address, amount);
                }
                self.pre_launch_holders_count.write(self.pre_launch_holders_count.read() + 1);
                i += 1;
            };
            assert(initial_minted_supply <= initial_supply, 'Unruggable: max supply reached');
        }
    }
}
