module DatabaseTypesHelper
  def database_type_icon_url(slug)
    case slug
    when "postgresql"
      "data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KPHBhdGggZD0iTTEyIDJMMTMuMDkgOC4yNkwyMCA5TDEzLjA5IDE1Ljc0TDEyIDIyTDEwLjkxIDE1Ljc0TDQgOUwxMC45MSA4LjI2TDEyIDJaIiBzdHJva2U9IiMzMzY3OTEiIHN0cm9rZS13aWR0aD0iMiIgZmlsbD0iIzMzNjc5MSIvPgo8L3N2Zz4K"
    when "mysql"
      "data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KPHBhdGggZD0iTTEyIDJMMTMuMDkgOC4yNkwyMCA5TDEzLjA5IDE1Ljc0TDEyIDIyTDEwLjkxIDE1Ljc0TDQgOUwxMC45MSA4LjI2TDEyIDJaIiBzdHJva2U9IiNmZjY5MDAiIHN0cm9rZS13aWR0aD0iMiIgZmlsbD0iI2ZmNjkwMCIvPgo8L3N2Zz4K"
    when "mongodb"
      "data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KPHBhdGggZD0iTTEyIDJMMTMuMDkgOC4yNkwyMCA5TDEzLjA5IDE1Ljc0TDEyIDIyTDEwLjkxIDE1Ljc0TDQgOUwxMC45MSA4LjI2TDEyIDJaIiBzdHJva2U9IiM0N2E0NDgiIHN0cm9rZS13aWR0aD0iMiIgZmlsbD0iIzQ3YTQ0OCIvPgo8L3N2Zz4K"
    when "cassandra"
      "data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KPHBhdGggZD0iTTEyIDJMMTMuMDkgOC4yNkwyMCA5TDEzLjA5IDE1Ljc0TDEyIDIyTDEwLjkxIDE1Ljc0TDQgOUwxMC45MSA4LjI2TDEyIDJaIiBzdHJva2U9IiMxMjg3YjgiIHN0cm9rZS13aWR0aD0iMiIgZmlsbD0iIzEyODdiOCIvPgo8L3N2Zz4K"
    else
      "data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KPGVsbGlwc2UgY3g9IjEyIiBjeT0iNiIgcng9IjgiIHJ5PSIzIiBzdHJva2U9IiM2Yjcy4OCIgc3Ryb2tlLXdpZHRoPSIyIi8+CjxwYXRoIGQ9Ik00IDZ2NmE4IDMgMCAwIDAgMTYgMHYtNiIgc3Ryb2tlPSIjNmI3Mjg4IiBzdHJva2Utd2lkdGg9IjIiLz4KPHBhdGggZD0iTTQgMTJ2NmE4IDMgMCAwIDAgMTYgMHYtNiIgc3Ryb2tlPSIjNmI3Mjg4IiBzdHJva2Utd2lkdGg9IjIiLz4KPC9zdmc+Cg=="
    end
  end

  def database_type_status_badge(database_type)
    if database_type.handler_available?
      content_tag :span, class: "badge bg-green" do
        concat content_tag(:svg, xmlns: "http://www.w3.org/2000/svg", class: "icon icon-sm", width: "24", height: "24", viewBox: "0 0 24 24", "stroke-width": "2", stroke: "currentColor", fill: "none", "stroke-linecap": "round", "stroke-linejoin": "round") do
          concat content_tag(:path, "", stroke: "none", d: "M0 0h24v24H0z", fill: "none")
          concat content_tag(:path, "", d: "M5 12l5 5l10 -10")
        end
        concat " Handler Available"
      end
    else
      content_tag :span, class: "badge bg-red" do
        concat content_tag(:svg, xmlns: "http://www.w3.org/2000/svg", class: "icon icon-sm", width: "24", height: "24", viewBox: "0 0 24 24", "stroke-width": "2", stroke: "currentColor", fill: "none", "stroke-linecap": "round", "stroke-linejoin": "round") do
          concat content_tag(:path, "", stroke: "none", d: "M0 0h24v24H0z", fill: "none")
          concat content_tag(:path, "", d: "M18 6l-12 12")
          concat content_tag(:path, "", d: "M6 6l12 12")
        end
        concat " No Handler"
      end
    end
  end

  def version_default_badge(version)
    if version.is_default?
      content_tag :span, "Default", class: "badge bg-yellow"
    else
      content_tag :span, "—", class: "text-muted"
    end
  end

  def config_template_status(version)
    if version.config_template.present?
      content_tag :span, class: "badge bg-green" do
        concat content_tag(:svg, xmlns: "http://www.w3.org/2000/svg", class: "icon icon-sm", width: "24", height: "24", viewBox: "0 0 24 24", "stroke-width": "2", stroke: "currentColor", fill: "none", "stroke-linecap": "round", "stroke-linejoin": "round") do
          concat content_tag(:path, "", stroke: "none", d: "M0 0h24v24H0z", fill: "none")
          concat content_tag(:path, "", d: "M5 12l5 5l10 -10")
        end
        concat " Available"
      end
    else
      content_tag :span, "None", class: "badge bg-gray"
    end
  end

  def installation_complexity_badge(complexity)
    case complexity
    when "simple"
      content_tag :span, complexity.humanize, class: "badge bg-green"
    when "medium"
      content_tag :span, complexity.humanize, class: "badge bg-yellow"
    when "complex"
      content_tag :span, complexity.humanize, class: "badge bg-red"
    else
      content_tag :span, complexity.humanize, class: "badge bg-gray"
    end
  end

  def replication_support_badge(supports)
    if supports
      content_tag :span, "✓ Supported", class: "badge bg-green"
    else
      content_tag :span, "✗ Not supported", class: "badge bg-red"
    end
  end
end
