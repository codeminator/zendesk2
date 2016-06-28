# frozen_string_literal: true
class Zendesk2::GetHelpCenterCategoriesSections
  include Zendesk2::Request

  request_path do |r|
    locale = r.params['locale']
    locale ? "/help_center/#{locale}/categories/#{r.category_id}/sections.json" : "/help_center/categories/#{r.category_id}/sections.json"
  end

  page_params!

  def category_id
    Integer(
      params.fetch('category_id')
    )
  end

  def mock
    find!(:help_center_categories, category_id)

    mock_response('sections' => data[:help_center_sections].values.select { |s| s['category_id'] == category_id })
  end
end
