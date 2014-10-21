class Zendesk2::Client::GetForum < Zendesk2::Client::Request
  request_method :get
  request_path { |r| "/forums/#{r.forum_id}.json" }

  def forum_id
    params.fetch("forum").fetch("id")
  end

  def mock
    mock_response(
      "forum" => find!(:forums, forum_id)
    )
  end
end
