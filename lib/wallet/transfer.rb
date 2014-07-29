module RubyWallet
  class Transfer
    include Mongoid::Document

    field :timestamp,      type: Time

    field :sender_id,      type: String
    field :recipeint_id,   type: String

    field :category,       type: String
    field :amount,         type: BigDecimal
       
    field :comment,        type: String

    embedded_in :wallet

    validates :category, format: { with: /^(send|receive)$/ }
    validates :amount, format: { with: /^\d{0,8}(\.\d{1,8}|)/ }
    validate :amount_check

    def sender
      self.wallet.accounts.find(self.sender_id)
    end

    def recipient
      self.wallet.accounts.find(self.recipient_id)
    end

    protected

      def amount_check
        if self.category == "send"
          self.amount < 0
        else
          self.amount > 0
        end
      end

  end
end
