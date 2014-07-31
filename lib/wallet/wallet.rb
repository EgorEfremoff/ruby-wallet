module RubyWallet
  class Wallet
    include Mongoid::Document
    #include Mongoid::Paranoia
    include Coind

    field :iso_code,                  type: String

    field :rpc_user,                  type: String
    field :rpc_password,              type: Mongoid::EncryptedString
    field :rpc_host,                  type: String
    field :rpc_port,                  type: Integer
    field :rpc_ssl,                   type: Boolean

    field :encrypted,                 type: Boolean
    field :wallet_password,           type: Mongoid::EncryptedString

    field :unconfirmed_balance,       type: BigDecimal,                default: 0
    field :confirmed_balance,         type: BigDecimal,                default: 0

    field :confirmations,             type: Integer

    field :transaction_checked_count, type: Integer,                   default: 0
    field :last_updated,              type: Time,                      default: Time.now

    embeds_many :accounts
    embeds_many :transactions
    embeds_many :transfers

    validates_uniqueness_of :iso_code

    def encrypt
      if coind.encrypt(wallet_password)
        update_attributes(wallet_encrypted: true)
      end
    end

    def account?(label)
      accounts.find_by(label: label)
    end

    def transaction?(transaction_id)
      transactions.find_by(transaction_id: transaction_id)
    end

    def transfer(sender, recipient, amount, comment = nil)
      if amount > 0 and sender.confirmed_balance >= amount and confirmed_balance >= amount and accounts.find(recipient.id)
        # Subtract from the sender account
        create_transfer(sender_label:    sender.label,
                        sender_id:       sender.id,
                        recipient_label: recipient.label,
                        recipient_id:    recipeint.id,
                        category:        "send",
                        amount:          -amount,
                        comment:         comment
                       )
        # Add to the recipient account 
        create_transfer(sender_label:    sender.label,
                        sender_id:       sender.id,
                        recipient_label: recipient.label,
                        recipient_id:    recipeint.id,
                        category:        "receive",
                        amount:          amount,
                        comment:         comment
                       )
        sender.update_balances
        recipient.update_balances
      else
        false
      end
    end

    def withdraw(account, address, amount)
      if account.confirmed_balance >= amount and confirmed_balance >= amount and valid_address?(address)
        # Transaction fees should be handled higher in the stack
        txid = coind.sendtoaddress(address, amount, account.label)
        if txid['error'].nil?
          account.update_attributes(withdrawal_ids: account.withdrawal_ids.push(txid).uniq)
          account.update_balances
          txid
        else
          false
        end
      else
        false
      end
    end

    def create_account(label)
      accounts.create(label: label)
    end

    def generate_address(label)
      coind.getnewaddress(label)
    end

    def label?(address)
      response = validate_address(address)
      if !response["account"].nil?
        response["account"]
      elsif !response["error"].nil?
        response["error"]
      else
        response
      end
    end

    def own_address?(address)
      response = validate_address(address)
      if !response["ismine"].nil?
        response["ismine"]
      elsif !response["error"].nil?
        response["error"]
      else
        response
      end
    end

    def valid_address?(address)
      response = validate_address(address)
      if !response["isvalid"].nil?
        response["isvalid"]
      elsif !response["error"].nil?
        response["error"]
      else
        response
      end
    end

    def sync
      wallet_transactions = coind.listtransactions("*", 99999)
      reset_transactions if transaction_checked_count > wallet_transactions.length
      if wallet_transactions and transaction_checked_count != wallet_transactions.length
        wallet_transactions[transaction_checked_count..wallet_transactions.length].each do |transaction|
          update_attributes(transaction_checked_count: transaction_checked_count + 1)
          if ["send", "receive"].include?(transaction["category"])
            account = account?(transaction["account"])
            if account
              new_transaction = transactions.create(account_label:  transaction["account"],
                                                    transaction_id: transaction["txid"],
                                                    address:        transaction["address"],
                                                    amount:         BigDecimal.new(transaction["amount"].to_s),
                                                    confirmations:  transaction["confirmations"],
                                                    occurred_at:    (Time.at(transaction["time"]) if !transaction["time"].nil?),
                                                    received_at:    (Time.at(transaction["timereceived"]) if !transaction["timereceived"].nil?),
                                                    category:       transaction["category"]
                                                   )
              if transaction["category"] == "receive"
                account.update_attributes(deposit_ids: account.deposit_ids.push(transaction["txid"]).uniq, total_received: total_received?(account.label))
                if new_transaction.confirmations >= confirmations
                  new_transaction.confirm
                end
              end
              account.update_balances
            end
          end
        end
      end
      self.transactions.where(confirmed: false, category: "receive").each do |transaction|
        wallet_transaction = coind.get_transaction(transaction.transaction_id)
        p wallet_transaction.to_json
        transaction.update_attributes(confirmations: wallet_transaction['confirmations'])
        if transaction.confirmations >= confirmations
          transaction.confirm
        end
      end
      update_balances
      update_attributes(last_update: Time.now)
    end 

    def sync_transaction(transaction_id)
      transaction = transaction?(transaction_id)
      if transaction
        wallet_transaction = coind.get_transaction(transaction_id)
        unless transaction.confirmed?
          transaction.update_attributes(confirmations: wallet_transaction['confirmations'])
          if transaction.confirmations >= confirmations
            transaction.confirm
          end
        end
      else
        sync
      end 
    end

    private

      def coind
        @client ||= Coind({:rpc_user =>    self.rpc_user,
                          :rpc_password => self.rpc_password,
                          :rpc_host =>     self.rpc_host,
                          :rpc_port =>     self.rpc_port,
                          :rpc_ssl =>      self.rpc_ssl})
      end

      def unlock(timeout = 20, &block)
        coind.unlock(self.wallet_password, timeout)
        if block
          block.call
          coind.lock
        end
      end
  
      def validate_address(address)
        coind.validateaddress(address)
      end

      def update_balances
        update_attributes(unconfirmed_balance: coind.balance(0),
                          confirmed_balance:   coind.balance(confirmations)
                         )
      end

      def reset_transactions
        transactions.destroy
        update_attributes(transction_checked_count: 0)
      end

      def total_received?(label)
        coind.getreceivedbylabel(label)
      end

  end
end
