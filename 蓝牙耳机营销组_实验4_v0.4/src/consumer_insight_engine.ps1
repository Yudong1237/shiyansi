param(
    [string]$InputCsv = "C:\Users\HP\Desktop\蓝牙耳机营销组_实验3_v0.3\data\processed\clean_data.csv",
    [string]$OutputRoot = "C:\Users\HP\Desktop\蓝牙耳机营销组_实验4_v0.4",
    [int]$ReviewsPerProduct = 2
)

$ErrorActionPreference = "Stop"
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8File([string]$Path, [string]$Content) {
    [System.IO.File]::WriteAllText($Path, $Content, $utf8)
}

function Get-NormalizedText([string]$Text) {
    if ($null -eq $Text) { return "" }
    return (($Text.ToLowerInvariant() -replace "\s+", "") -replace "[,.!?]", "")
}

function Get-Sha256([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Get-Topics([string]$Text) {
    $topicMap = [ordered]@{
        "音质" = @("音质", "声音", "低音", "高音", "通透", "解析")
        "续航" = @("续航", "电量", "电池", "充电", "耗电")
        "降噪" = @("降噪", "噪音", "通透模式", "环境声")
        "舒适度" = @("舒适", "佩戴", "耳朵", "夹耳", "硌", "松")
        "价格" = @("价格", "贵", "便宜", "性价比", "优惠")
        "配送" = @("配送", "物流", "快递", "到货", "发货")
        "包装" = @("包装", "盒子", "配件", "说明书")
        "连接" = @("连接", "蓝牙", "断连", "延迟", "配对")
    }
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($topic in $topicMap.Keys) {
        foreach ($word in $topicMap[$topic]) {
            if ($Text -like "*$word*") { $found.Add($topic); break }
        }
    }
    if ($found.Count -eq 0) { $found.Add("其他") }
    return @($found)
}

function Get-Sentiment([string]$Text, [int]$Rating) {
    $positiveWords = @("清晰", "满意", "舒服", "稳定", "喜欢", "轻便", "惊喜", "划算", "完整", "快速", "不错", "优秀")
    $negativeWords = @("差", "短", "掉电", "断连", "延迟", "夹耳", "硌", "贵", "慢", "破损", "失望", "噪音", "不满")
    $positive = 0; $negative = 0
    foreach ($word in $positiveWords) { if ($Text -like "*$word*") { $positive++ } }
    foreach ($word in $negativeWords) { if ($Text -like "*$word*") { $negative++ } }
    if ($Rating -ge 4 -and $positive -ge $negative) { return "positive" }
    if ($Rating -le 2 -or $negative -gt $positive) { return "negative" }
    return "neutral"
}

function Get-ReviewTemplate([int]$Pattern, [string]$Product, [int]$Price) {
    switch ($Pattern) {
        0 { return @{ Text = "${Product}音质清晰，人声自然，续航也稳定，通勤使用很满意。"; Rating = 5 } }
        1 { return @{ Text = "${Product}佩戴开始有点夹耳，续航偏短，使用几小时后需要充电。"; Rating = 2 } }
        2 { return @{ Text = "${Product}佩戴轻便舒服，包装完整，连接稳定，整体体验不错。"; Rating = 4 } }
        3 { return @{ Text = "${Product}价格${Price}元略贵，物流到货较慢，和预期有差距。"; Rating = 2 } }
        4 { return @{ Text = "${Product}降噪效果明显，地铁里能压住噪音，但偶尔有轻微延迟。"; Rating = 4 } }
        5 { return @{ Text = "${Product}蓝牙配对很快，声音通透，配件齐全，性价比不错。"; Rating = 5 } }
        6 { return @{ Text = "${Product}降噪一般，环境噪音仍然明显，偶尔断连，体验不太稳定。"; Rating = 2 } }
        default { return @{ Text = "${Product}外观简洁，音质和续航中规中矩，没有明显惊喜。"; Rating = 3 } }
    }
}

New-Item -ItemType Directory -Force -Path $OutputRoot, "$OutputRoot\data", "$OutputRoot\reports", "$OutputRoot\docs", "$OutputRoot\src", "$OutputRoot\dashboard", "$OutputRoot\prompt" | Out-Null
$products = @(Import-Csv -LiteralPath $InputCsv)
if ($products.Count -eq 0) { throw "InputCsv contains no rows." }

$retrievedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$reviews = New-Object System.Collections.Generic.List[object]
$rowNo = 0
foreach ($product in $products) {
    $price = [int][math]::Round([double]$product.price)
    for ($rep = 0; $rep -lt $ReviewsPerProduct; $rep++) {
        $pattern = ($rowNo + $rep * 3) % 8
        $template = Get-ReviewTemplate -Pattern $pattern -Product $product.product_name -Price $price
        $publish = [datetime]::Parse($product.publish_date)
        $reviewDate = $publish.AddDays(($rowNo % 17) + $rep + 1).ToString("yyyy-MM-dd")
        $repCode = "B"
        if ($rep -eq 0) { $repCode = "A" }
        $reviewId = "SIM-{0:D4}-{1}" -f ($rowNo + 1), $repCode
        $topics = @(Get-Topics $template.Text)
        $sentiment = Get-Sentiment -Text $template.Text -Rating $template.Rating
        $quote = $template.Text.Substring(0, [math]::Min(32, $template.Text.Length))
        $reviews.Add([pscustomobject]@{
            review_id = $reviewId
            source = "synthetic_from_clean_data"
            source_url = "local://clean_data.csv/$($product.record_id)"
            product_id = $product.record_id
            product = $product.product_name
            brand = $product.brand
            platform = $product.platform
            price = $price
            review_text = $template.Text
            rating = $template.Rating
            rating_scale = 5
            review_date = $reviewDate
            language = "zh"
            verified_purchase = "unknown"
            retrieved_at = $retrievedAt
            sentiment = $sentiment
            topics = ($topics -join ";")
            evidence_quote = $quote
            semantic_method = "transparent_keyword_rules_v1"
            simulated = "true"
        })
        $rowNo++
    }
}

$reviews = $reviews.ToArray()
$reviews | Export-Csv -LiteralPath "$OutputRoot\data\reviews_encoded.csv" -NoTypeInformation -Encoding UTF8
$jsonReviews = foreach ($r in $reviews) {
    [ordered]@{
        review_id = $r.review_id; source = $r.source; source_url = $r.source_url; product = $r.product
        review_text = $r.review_text; rating = [int]$r.rating; rating_scale = 5; review_date = $r.review_date
        language = $r.language; verified_purchase = $null; retrieved_at = $r.retrieved_at
        sentiment = $r.sentiment; topics = @($r.topics -split ";"); raw = @{ product_id = $r.product_id; brand = $r.brand; platform = $r.platform; simulated = $true }
    }
}
Write-Utf8File "$OutputRoot\data\reviews_normalized.json" (($jsonReviews | ConvertTo-Json -Depth 6))

$topicRows = foreach ($topic in ($reviews.topics -split ";" | Where-Object { $_ } | Sort-Object -Unique)) {
    $mentions = @($reviews | Where-Object { $_.topics -split ";" -contains $topic })
    $negative = @($mentions | Where-Object sentiment -eq "negative")
    [pscustomobject]@{ topic = $topic; mentions = $mentions.Count; negative_mentions = $negative.Count; negative_share_pct = [math]::Round(100 * $negative.Count / [math]::Max(1, $mentions.Count), 2); evidence_ids = (($negative | Select-Object -First 3 -ExpandProperty review_id) -join ";") }
}
$topicRows = @($topicRows | Sort-Object negative_mentions,mentions -Descending)
$topicRows | Export-Csv -LiteralPath "$OutputRoot\reports\pain_points_ranked.csv" -NoTypeInformation -Encoding UTF8

$brandRows = foreach ($brand in ($reviews.brand | Sort-Object -Unique)) {
    $subset = @($reviews | Where-Object brand -eq $brand)
    [pscustomobject]@{ brand = $brand; sample_n = $subset.Count; avg_rating = [math]::Round((($subset | Measure-Object rating -Average).Average), 2); positive_pct = [math]::Round(100 * (@($subset | Where-Object sentiment -eq "positive").Count) / $subset.Count, 2); negative_pct = [math]::Round(100 * (@($subset | Where-Object sentiment -eq "negative").Count) / $subset.Count, 2); top_topic = (($subset.topics -split ";" | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name) }
}
$monthRows = foreach ($month in ($reviews.review_date.Substring(0,7) | Sort-Object -Unique)) {
    $subset = @($reviews | Where-Object { $_.review_date.StartsWith($month) })
    [pscustomobject]@{ month = $month; sample_n = $subset.Count; avg_rating = [math]::Round((($subset | Measure-Object rating -Average).Average), 2); positive_pct = [math]::Round(100 * (@($subset | Where-Object sentiment -eq "positive").Count) / $subset.Count, 2); negative_pct = [math]::Round(100 * (@($subset | Where-Object sentiment -eq "negative").Count) / $subset.Count, 2) }
}
$brandRows + $monthRows | Export-Csv -LiteralPath "$OutputRoot\reports\brand_time_comparison.csv" -NoTypeInformation -Encoding UTF8

$sentimentCounts = @("positive","neutral","negative" | ForEach-Object { $label = $_; [pscustomobject]@{ metric = "sentiment_$label"; value = @($reviews | Where-Object sentiment -eq $label).Count } })
$ratingCounts = @(1,2,3,4,5 | ForEach-Object { $rating = $_; [pscustomobject]@{ metric = "rating_$rating"; value = @($reviews | Where-Object { [int]$_.rating -eq $rating }).Count } })
$summary = @(
    [pscustomobject]@{ metric="review_count"; value=$reviews.Count }
    [pscustomobject]@{ metric="product_count"; value=@($reviews.product_id | Sort-Object -Unique).Count }
    [pscustomobject]@{ metric="avg_rating"; value=[math]::Round((($reviews | Measure-Object rating -Average).Average),2) }
    [pscustomobject]@{ metric="date_min"; value=($reviews.review_date | Sort-Object | Select-Object -First 1) }
    [pscustomobject]@{ metric="date_max"; value=($reviews.review_date | Sort-Object | Select-Object -Last 1) }
    [pscustomobject]@{ metric="duplicate_review_id"; value=($reviews.review_id | Group-Object | Where-Object Count -gt 1).Count }
    [pscustomobject]@{ metric="missing_review_text"; value=@($reviews | Where-Object { [string]::IsNullOrWhiteSpace($_.review_text) }).Count }
    [pscustomobject]@{ metric="missing_evidence_quote"; value=@($reviews | Where-Object { [string]::IsNullOrWhiteSpace($_.evidence_quote) }).Count }
) + $sentimentCounts + $ratingCounts
$summary | Export-Csv -LiteralPath "$OutputRoot\reports\summary_stats.csv" -NoTypeInformation -Encoding UTF8

$spot = @($reviews | Sort-Object review_id | Select-Object -First 10 | ForEach-Object {
    [pscustomobject]@{ review_id=$_.review_id; product_id=$_.product_id; original_text=$_.review_text; expected_sentiment=$_.sentiment; encoded_topics=$_.topics; evidence_quote=$_.evidence_quote; reviewable="yes"; reviewer_note="规则命中可复核" }
})
$spot | Export-Csv -LiteralPath "$OutputRoot\reports\spot_check_10.csv" -NoTypeInformation -Encoding UTF8

$evidence = @($reviews | Where-Object sentiment -eq "negative" | Select-Object -First 30 | ForEach-Object {
    [pscustomobject]@{ priority = "P1"; review_id=$_.review_id; product_id=$_.product_id; brand=$_.brand; topic=$_.topics; evidence_quote=$_.evidence_quote; claim="该条模拟评论表达负向体验"; claim_type="事实编码"; verification_status="待人工复核" }
})
$evidence | Export-Csv -LiteralPath "$OutputRoot\reports\evidence_traceability.csv" -NoTypeInformation -Encoding UTF8

$topPain = ($topicRows | Select-Object -First 5 | ForEach-Object { "| $($_.topic) | $($_.mentions) | $($_.negative_mentions) | $($_.negative_share_pct)% | $($_.evidence_ids) |" }) -join "`n"
$topBrands = ($brandRows | ForEach-Object { "| $($_.brand) | $($_.sample_n) | $($_.avg_rating) | $($_.positive_pct)% | $($_.negative_pct)% | $($_.top_topic) |" }) -join "`n"
$report = @"
# 实验四：AI+PowerShell 消费者洞察引擎 v0.4

## 结论摘要

本报告分析 $($reviews.Count) 条**模拟评论**，覆盖 $(@($reviews.product_id | Sort-Object -Unique).Count) 个商品。评论由实验三清洗商品数据按固定模板生成，不是电商平台实采样本，不能外推真实市场份额或消费者总体态度。

程序完成读取、去重检查、字段统计、分组计数和百分比计算；语义编码使用 transparent_keyword_rules_v1 作为可复核代理规则，并保留原文、主题、情绪和证据摘录。建议将规则编码结果交由人工复核后再用于正式决策。

## 痛点排序

| 主题 | 提及数 | 负向提及 | 负向占该主题 | 证据ID |
|---|---:|---:|---:|---|
$topPain

排名只表示本模拟样本中的规则命中频次；“负向占该主题”分母为该主题提及样本量，不等于总体满意度。

## 品牌对比

| 品牌 | 样本量 | 平均评分 | 正向占比 | 负向占比 | 高频主题 |
|---|---:|---:|---:|---:|---|
$topBrands

## 事实、推断与建议

- **事实**：详见 reports/summary_stats.csv、reports/pain_points_ranked.csv，每个比例都带有样本量和分母。
- **推断**：如果后续真实评论也反复出现续航、舒适度或连接问题，可优先安排固件、电池和佩戴结构的验证。
- **建议**：先对 reports/spot_check_10.csv 和 reports/evidence_traceability.csv 做人工抽检，再决定是否扩大样本或调整关键词规则。

## 方法与限制

1. 输入是实验三 clean_data.csv 的 320 条商品记录；每个商品生成 2 条模拟中文评论，共 640 条。
2. 生成过程固定模板、无个人信息、无外部抓取；simulated=true 和 source=synthetic_from_clean_data 明确标识来源。
3. 主题和情绪由透明关键词规则编码，不把规则命中当作因果结论；短文本、反讽、图片评论和上下文缺失会造成误判。
4. 结果是模拟样本的描述性统计，不是平台总体估计。真实项目应使用用户授权导出、官方 API 或公开可访问来源，并记录访问时间与样本框。

生成时间：$retrievedAt
"@
Write-Utf8File "$OutputRoot\reports\consumer_insight_report.md" $report

$manifest = [ordered]@{
    run_id = "exp4-$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))"
    started_at = $retrievedAt
    finished_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    source = "local clean_data.csv"
    source_path = $InputCsv
    collection_method = "synthetic deterministic generation from user-provided local dataset"
    requested_count = $products.Count * $ReviewsPerProduct
    record_count = $reviews.Count
    duplicate_count = ($reviews.review_id | Group-Object | Where-Object Count -gt 1).Count
    error_count = 0
    date_range = @{ min = ($reviews.review_date | Sort-Object | Select-Object -First 1); max = ($reviews.review_date | Sort-Object | Select-Object -Last 1) }
    language = "zh"
    limitations = @("模拟评论，不代表真实消费者总体", "规则编码需要人工复核", "商品字段没有真实评论上下文")
}
Write-Utf8File "$OutputRoot\reports\run_manifest.json" ($manifest | ConvertTo-Json -Depth 6)

$prompt = @"
# 语义编码 Prompt（人工/AI复核模板）

你是消费者评论编码助手。输入字段为 review_id、review_text、rating、brand、review_date。

请输出 JSON：sentiment（positive/neutral/negative）、topics（仅限音质、续航、降噪、舒适度、价格、配送、包装、连接、其他）、evidence_quote（原文连续短摘录）、confidence（0-1）、uncertainty_reason。

约束：保留原始 review_id；不要补写评论没有表达的事实；一条评论可有多个主题；反讽、图片、口语或上下文不足时降低 confidence；程序负责计数、排序和百分比，模型只负责语义编码。

本次运行的实际编码方法是 transparent_keyword_rules_v1，不是外部大模型调用，所有结果需人工抽检。
"@
Write-Utf8File "$OutputRoot\prompt\semantic_encoding_prompt.md" $prompt

$docs = @"
# 数据与伦理说明

- 输入：实验三生成的 clean_data.csv，包含 320 条模拟商品记录。
- 输出：640 条模拟评论，来源字段为 synthetic_from_clean_data，不含真实姓名、账号、联系方式。
- 不进行登录、绕过验证、抓取平台或声称代表真实市场。
- 任何外部发布前，必须将模拟数据与真实授权导出分开存储，并重新生成运行清单。
- 完成抽检后再调整规则；禁止只凭自动标签宣称因果关系。
"@
Write-Utf8File "$OutputRoot\docs\method_and_limitations.md" $docs

$html = @"
<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>消费者洞察 Dashboard v0.4</title>
<style>body{font-family:Segoe UI,Microsoft YaHei,sans-serif;margin:32px;color:#203040;background:#f5f7fa}h1{color:#123b5d}.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:14px}.card{background:#fff;border:1px solid #dce3ea;padding:16px;border-radius:6px}.num{font-size:28px;font-weight:700;color:#0b7285}.warn{background:#fff4e5;border-left:4px solid #f08c46;padding:12px;margin:18px 0}table{border-collapse:collapse;width:100%;background:#fff}th,td{padding:9px;border-bottom:1px solid #e5e7eb;text-align:left}th{background:#123b5d;color:white}</style></head><body>
<h1>消费者洞察 Dashboard v0.4</h1><div class="warn">数据性质：640 条由实验三商品数据生成的模拟评论，不能代表真实平台样本。</div>
<div class="grid"><div class="card"><div>评论数</div><div class="num">$($reviews.Count)</div></div><div class="card"><div>商品数</div><div class="num">$(@($reviews.product_id | Sort-Object -Unique).Count)</div></div><div class="card"><div>平均评分</div><div class="num">$([math]::Round((($reviews | Measure-Object rating -Average).Average),2))</div></div><div class="card"><div>规则版本</div><div class="num" style="font-size:18px">v1</div></div></div>
<h2>痛点排名</h2><table><tr><th>主题</th><th>提及数</th><th>负向数</th><th>负向占比</th></tr>$((($topicRows | Select-Object -First 8 | ForEach-Object { "<tr><td>$($_.topic)</td><td>$($_.mentions)</td><td>$($_.negative_mentions)</td><td>$($_.negative_share_pct)%</td></tr>" }) -join "`n"))</table>
<h2>使用说明</h2><p>详细证据见 <code>reports/evidence_traceability.csv</code>；10 条人工抽检见 <code>reports/spot_check_10.csv</code>；完整限制见 <code>reports/consumer_insight_report.md</code>。</p></body></html>
"@
Write-Utf8File "$OutputRoot\dashboard\dashboard.html" $html
Write-Host "Generated experiment 4 outputs in $OutputRoot"
