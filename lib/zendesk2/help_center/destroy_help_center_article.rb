# frozen_string_literal: true
class Zendesk2::DestroyHelpCenterArticle
  include Zendesk2::Request

  request_method :delete
  request_path { |r| "/help_center/articles/#{r.article_id}.json" }

  def article_id
    params.fetch('article').fetch('id')
  end

  def mock
    mock_response('article' => find!(:help_center_articles, article_id))
  end
end
