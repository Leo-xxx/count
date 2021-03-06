require 'rails_helper'

RSpec.describe Admin::ShakecamsController, type: :controller do
  it_behaves_like "an admin controller"

  describe "index" do
    render_views
    before do
      sign_in FactoryGirl.create(:admin)
      FactoryGirl.create(:shakecam)
    end

    it "renders correctly" do
      get :index
      expect(response).to be_ok
    end
  end
end
