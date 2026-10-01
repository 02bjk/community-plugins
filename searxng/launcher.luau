--!nonstrict
-- SearXNG search launcher provider.
--
-- Usage from launcher: `/sx <query>` or via global launcher search.
-- Queries SearXNG instance for private search results, instant answers, and snippets.

local DEFAULT_INSTANCE = "https://search.lumy.live"
local activeQuery = ""
local requestSequence = 0

local HTML_ENTITIES = {
  ["&amp;"] = "&",
  ["&lt;"] = "<",
  ["&gt;"] = ">",
  ["&quot;"] = "\"",
  ["&#39;"] = "'",
  ["&apos;"] = "'",
  ["&nbsp;"] = " ",
}

local function trim(s)
  if type(s) ~= "string" then
    return ""
  end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function sanitizeHtml(s)
  if type(s) ~= "string" or s == "" then
    return ""
  end
  -- Strip HTML tags
  local cleaned = s:gsub("<[^>]+>", "")
  -- Decode common HTML entities via lookup table
  cleaned = cleaned:gsub("&%w+;", HTML_ENTITIES)
  cleaned = cleaned:gsub("&#39;", "'")
  return trim(cleaned)
end

local function isValidUrl(url)
  if type(url) ~= "string" then
    return false
  end
  -- Strictly require http:// or https:// and disallow whitespace
  return url:match("^https?://%S+$") ~= nil
end

local function getInstanceUrl()
  local url = noctalia.getConfig("instance_url")
  if type(url) ~= "string" or url == "" then
    return DEFAULT_INSTANCE
  end
  url = trim(url)
  if not url:match("^https?://") then
    return DEFAULT_INSTANCE
  end
  return url:gsub("/+$", "")
end

local function buildResults(query, payload)
  local rows = {}
  local text = trim(query)

  -- 1. Direct Instant Answers
  if type(payload.answers) == "table" then
    for _, ans in ipairs(payload.answers) do
      local ansText = ""
      if type(ans) == "string" then
        ansText = sanitizeHtml(ans)
      elseif type(ans) == "table" and type(ans.answer) == "string" then
        ansText = sanitizeHtml(ans.answer)
      end

      if ansText ~= "" then
        table.insert(rows, {
          id = "answer:" .. ansText,
          title = ansText,
          subtitle = noctalia.tr("results.answer_subtitle"),
          glyph = "bulb",
          badge = noctalia.tr("results.answer_badge"),
          presentation = "detail",
          score = 600,
        })
      end
    end
  end

  -- 2. Web Search Results
  local maxResults = tonumber(noctalia.getConfig("max_results")) or 8
  if maxResults < 1 then
    maxResults = 1
  elseif maxResults > 20 then
    maxResults = 20
  end

  if type(payload.results) == "table" then
    local rank = 0
    for _, item in ipairs(payload.results) do
      if #rows >= maxResults then
        break
      end
      if type(item) == "table" and isValidUrl(item.url) then
        local title = sanitizeHtml(item.title)
        local content = sanitizeHtml(item.content)
        if title == "" then
          title = item.url
        end
        if content == "" then
          content = item.url
        end

        rank = rank + 1
        local engine = type(item.engine) == "string" and item.engine or nil
        table.insert(rows, {
          id = "url:" .. item.url,
          title = title,
          subtitle = content,
          badge = engine,
          glyph = "world",
          presentation = "detail",
          score = math.max(100, 500 - rank),
        })
      end
    end
  end

  -- 3. Empty State Handling
  if #rows == 0 then
    table.insert(rows, {
      id = "status",
      title = noctalia.tr("results.no_results_title"),
      subtitle = noctalia.tr("results.no_results_subtitle"),
      glyph = "info-circle",
      score = 100,
    })
  end

  -- 4. Always provide Fallback / Search Page Option
  local searchPageUrl = getInstanceUrl() .. "/search?q=" .. noctalia.string.urlEncode(text)
  table.insert(rows, {
    id = "url:" .. searchPageUrl,
    title = noctalia.tr("results.open_search_title", { query = text }),
    subtitle = searchPageUrl,
    glyph = "world-search",
    score = 50,
  })

  return rows
end

function onQuery(query)
  local text = trim(query)
  activeQuery = query
  requestSequence = requestSequence + 1
  local sequence = requestSequence

  if text == "" then
    launcher.setResults(query, {
      {
        id = "hint",
        title = noctalia.tr("hint.title"),
        subtitle = noctalia.tr("hint.subtitle"),
        glyph = "world-search",
        score = 200,
      },
    })
    return
  end

  local instance = getInstanceUrl()
  local searchPageUrl = instance .. "/search?q=" .. noctalia.string.urlEncode(text)

  -- Immediately display an actionable search row with loader so the UI never displays "no results found"
  launcher.setResults(query, {
    {
      id = "url:" .. searchPageUrl,
      title = noctalia.tr("results.open_search_title", { query = text }),
      subtitle = noctalia.tr("loading.title"),
      glyph = "loader",
      score = 500,
    },
  })

  local categories = noctalia.getConfig("categories")
  if type(categories) ~= "string" or categories == "" then
    categories = "general"
  end

  local safesearch = noctalia.getConfig("safesearch")
  if type(safesearch) ~= "string" or safesearch == "" then
    safesearch = "0"
  end

  local searchUrl = string.format(
    "%s/search?q=%s&format=json&categories=%s&safesearch=%s",
    instance,
    noctalia.string.urlEncode(text),
    noctalia.string.urlEncode(categories),
    noctalia.string.urlEncode(tostring(safesearch))
  )

  local req = {
    url = searchUrl,
    method = "GET",
    headers = {
      "Accept: application/json",
      "User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0",
    },
  }

  noctalia.http(req, function(response)
    if sequence ~= requestSequence or activeQuery ~= query then
      return
    end

    if not response.ok or response.status == 0 then
      launcher.setResults(query, {
        {
          id = "url:" .. searchPageUrl,
          title = noctalia.tr("results.open_search_title", { query = text }),
          subtitle = noctalia.tr("errors.network_subtitle"),
          glyph = "world-search",
          score = 500,
        },
      })
      return
    end

    if response.status >= 400 then
      launcher.setResults(query, {
        {
          id = "url:" .. searchPageUrl,
          title = noctalia.tr("results.open_search_title", { query = text }),
          subtitle = "HTTP " .. tostring(response.status) .. " - press Enter to search in browser",
          glyph = "world-search",
          score = 500,
        },
      })
      return
    end

    local decoded, err = noctalia.json.decode(response.body or "")
    if type(decoded) ~= "table" then
      launcher.setResults(query, {
        {
          id = "url:" .. searchPageUrl,
          title = noctalia.tr("results.open_search_title", { query = text }),
          subtitle = "Invalid JSON - press Enter to search in browser",
          glyph = "world-search",
          score = 500,
        },
      })
      return
    end

    local rows = buildResults(query, decoded)
    launcher.setResults(query, rows)
  end)
end

function onActivate(id)
  if type(id) ~= "string" then
    return
  end

  local url = id:match("^url:(https?://.+)$")
  if url ~= nil and isValidUrl(url) then
    noctalia.runAsync({ "xdg-open", url })
    return
  end

  local answer = id:match("^answer:(.+)$")
  if answer ~= nil then
    noctalia.copyToClipboard(answer, "text/plain")
    noctalia.notify(noctalia.tr("notify.copied_title"), answer)
    return
  end

  if id == "hint" then
    local instance = getInstanceUrl()
    noctalia.runAsync({ "xdg-open", instance })
    return
  end
end
