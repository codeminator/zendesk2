require 'spec_helper'

describe "users" do
  let(:client) { create_client }

  include_examples "zendesk resource", {
    :collection    => lambda { client.users },
    :create_params => lambda { { email: mock_email, name: mock_uuid, verified: true } },
    :update_params => lambda { { name: mock_uuid } },
  }

  it "should get current user" do
    current_user = client.users.current
    expect(current_user.email).to eq(client.username)
  end

  describe "#create_user" do
    it "should prevent duplicate external_ids" do
      external_id = mock_uuid

      client.create_user(email: mock_email, name: "a", external_id: nil)         # fine
      client.create_user(email: mock_email, name: "b", external_id: nil)         # also fine
      client.create_user(email: mock_email, name: "c", external_id: external_id) # it's cool

      expect {
        client.create_user(email:  mock_email, name: "d", external_id: external_id)
      }.to raise_exception(Zendesk2::Error, /External has already been taken/)
    end
  end

  describe "#update_user" do
    it "should prevent duplicate external_ids" do
      user         = client.users.create(email: mock_email, name: "a")
      another_user = client.users.create(email: mock_email, name: "b")

      external_id = mock_uuid

      client.update_user(id: user.id, external_id: nil)                 # fine
      client.update_user(id: another_user.id, external_id: external_id) # also fine

      expect {
        client.update_user("id" => user.id, external_id: external_id)
      }.to raise_exception(Zendesk2::Error, /External has already been taken/)
    end
  end

  describe "#search" do
    it "should find a user based on details criteria with wildcards and by organization name", mock_only: true do
      # detached user
      client.users.create!(email: mock_email, name: mock_uuid)

      # possible match
      bad_org = client.organizations.create!(name: mock_uuid)
      client.users.create!(email: mock_email, name: mock_uuid, organization: bad_org)

      org = client.organizations.create!(name: mock_uuid)
      user = client.users.create!(email: mock_email, name: mock_uuid, organization: org, details: "anything_hello-something-michelle")

      expect(client.users.search(details: "*michelle*", organization: org.name)).to contain_exactly(user)
      expect(client.users.search(details: "*michelle*", organization: org.name[0..6])).to include(user)
    end
  end

  describe "#save" do
    let!(:user) { client.users.create!(email: mock_email, name: mock_uuid) }

    it "should update organization" do
      user.organization = organization = client.organizations.create!(name: mock_uuid)

      user.save!

      expect(user.organization).to eq(organization)
    end

    it "should get requested tickets" do
      ticket = client.tickets.create!(requester: user, subject: mock_uuid, description: mock_uuid)

      expect(user.requested_tickets).to include ticket
    end

    it "should get ccd tickets", mock_only: true do
      ticket = client.tickets.create!(collaborators: [user], subject: mock_uuid, description: mock_uuid)

      expect(user.ccd_tickets).to include ticket
    end

    it "cannot destroy a user with a ticket" do
      client.tickets.create!(requester: user, subject: mock_uuid, description: mock_uuid)

      expect(user.destroy).to be_falsey

      expect(user).not_to be_destroyed
    end

    it "should list identities" do
      identities = user.identities.all
      expect(identities.size).to eq(1)

      identity = identities.first
      expect(identity.primary).to be_truthy
      expect(identity.verified).to be_falsey
      expect(identity.type).to eq("email")
      expect(identity.value).to eq(user.email)
    end

    it "should create a new identity" do
      email = "ey+#{mock_uuid}@example.org"

      new_identity = user.identities.create!(type: "email", value: email)

      expect(new_identity.primary).to be_falsey
      expect(new_identity.verified).to be_falsey
      expect(new_identity.type).to eq("email")
      expect(new_identity.value).to eq(email)
    end

    it "should mark remaining identity as primary" do
      email = "ey+#{mock_uuid}@example.org"

      initial_identity = user.identities.all.first
      new_identity     = user.identities.create!(type: "email", value: email)

      expect {
        initial_identity.destroy
      }.to change { user.identities.all }.
        from(a_collection_containing_exactly(initial_identity, new_identity)).
        to(a_collection_containing_exactly(new_identity))

      expect(new_identity.reload.primary).to be_falsey

      new_identity.primary!

      expect(new_identity.reload.primary).to be_truthy
    end

    it "should not allow multiple primary identities" do
      email = "ey+#{mock_uuid}@example.org"

      initial_identity = user.identities.all.first
      new_identity     = user.identities.create!(type: "email", value: email)
      new_identity.primary!
      expect(new_identity.primary).to be_truthy
      expect(new_identity.reload.primary).to be_truthy

      expect(initial_identity.reload.primary).to be_falsey
    end

    it "should hate non-unique emails" do
      email = mock_email
      client.users.create!(email: email, name: mock_uuid)
      expect { client.users.create!(email: email, name: mock_uuid) }.to raise_exception(Zendesk2::Error)

      user = client.users.create(email: email, name: mock_uuid)

      expect(user.identity).to eq(nil)
      expect(user.errors).to eq({"email" => ["Email: #{email} is already being used by another user"]})
    end

    it "should create another identity when updating email" do
      expect(user.identities.size).to eq(1)

      original_email = user.email
      user.email = (new_email = mock_email)

      expect {
        user.save!
      }.to change { user.identities.size }.by(1)

      new_identity = user.identities.find { |i| i.value == new_email }

      expect(new_identity).to be
      expect(new_identity.primary).to eq(false)

      original_identity = user.identities.find { |i| i.value == original_email }

      expect(original_identity).to be
      expect(original_identity.primary).to eq(true)
      expect(user.reload.email).to eq(original_email)

      expect {
        user.save!
      }.not_to change { user.identities.size }
    end

    it "should form 'legacy' login url" do
      return_to = "http://engineyard.com"
      uri = Addressable::URI.parse(user.login_url(Time.now.to_s, return_to: return_to, token: "in-case-you-dont-have-it-in ~/.zendesk2 (aka ci)"))
      expect(uri.query_values["return_to"]).to eq(return_to)
      expect(uri.query_values["name"]).to eq user.name
      expect(uri.query_values["email"]).to eq user.email
      expect(uri.query_values["hash"]).not_to be_nil
    end

    it "should form jwt login url" do
      return_to = "http://engineyard.com"
      uri = Addressable::URI.parse(user.jwt_login_url(return_to: return_to, jwt_token: "in-case-you-dont-have-it-in ~/.zendesk2 (aka ci)"))
      expect(uri.query_values["return_to"]).to eq(return_to)
      expect(uri.query_values["name"]).to be_nil
      expect(uri.query_values["email"]).to be_nil
      expect(uri.query_values["jwt"]).not_to be_nil

      #TODO: try JWT.decode
    end

  end
end
