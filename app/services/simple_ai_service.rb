class SimpleAiService
  require 'net/http'
  require 'json'
  # Configuration for different AI services
  GROQ_API_KEY = "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"
  ANTHROPIC_API_KEY = ENV['ANTHROPIC_API_KEY']
  OPENROUTER_API_KEY = "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"

  
  def initialize(description)
    @description = description
    @timeout = 30
  end

  def generate
    Rails.logger.info "Simple AI generation started for: #{@description}"
    
    # Try different AI services in order of preference
    ai_response = try_groq_api || try_anthropic_api || try_openrouter_api
    if ai_response.present?
      Rails.logger.info "Simple AI generation successful: #{ai_response.length} chars"
      return ai_response
    else
      Rails.logger.warn "Simple AI generation failed, using template"
      return generate_with_smart_template
    end
  end

  private

  def try_groq_api
    return nil unless GROQ_API_KEY.present?
    
    begin
      Rails.logger.info "Trying Groq API"
      
      uri = URI('https://api.groq.com/openai/v1/chat/completions')
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = @timeout
      
      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{GROQ_API_KEY}"
      request['Content-Type'] = 'application/json'
      request.body = {
        model: 'llama3-70b-8192',
        messages: [
          {
            role: 'system',
            content: 'You are a professional contract lawyer. Generate a complete, legally sound contract based on the user\'s description.'
          },
          {
            role: 'user',
            content: build_contract_prompt(@description)
          }
        ],
        max_tokens: 2000,
        temperature: 0.7
      }.to_json
      #test
      response = http.request(request)
      if response.code == '200'
        result = JSON.parse(response.body)
        if result.dig('choices', 0, 'message', 'content')
          return result['choices'][0]['message']['content'].strip
        end
      else
        Rails.logger.error "Groq API error: #{response.code} - #{response.body}"
      end
      
      return nil
    rescue => e
      Rails.logger.error "Groq API call failed: #{e.message}"
      return nil
    end
  end

  def try_anthropic_api
    return nil unless ANTHROPIC_API_KEY.present?
    
    begin
      Rails.logger.info "Trying Anthropic API"
      
      uri = URI('https://api.anthropic.com/v1/messages')
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = @timeout
      
      request = Net::HTTP::Post.new(uri)
      request['x-api-key'] = ANTHROPIC_API_KEY
      request['Content-Type'] = 'application/json'
      request['anthropic-version'] = '2023-06-01'
      
      request.body = {
        model: 'claude-3-sonnet-20240229',
        max_tokens: 2000,
        messages: [
          {
            role: 'user',
            content: build_contract_prompt(@description)
          }
        ]
      }.to_json
      
      response = http.request(request)
      
      if response.code == '200'
        result = JSON.parse(response.body)
        if result.dig('content', 0, 'text')
          return result['content'][0]['text'].strip
        end
      else
        Rails.logger.error "Anthropic API error: #{response.code} - #{response.body}"
      end
      
      return nil
    rescue => e
      Rails.logger.error "Anthropic API call failed: #{e.message}"
      return nil
    end
  end

  def try_openrouter_api
    return nil unless OPENROUTER_API_KEY && !OPENROUTER_API_KEY.empty?

    begin
      Rails.logger.info "Trying OpenRouter API"

      uri = URI("https://openrouter.ai/api/v1/chat/completions")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = @timeout

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{OPENROUTER_API_KEY}"
      request["Content-Type"] = "application/json"

      request.body = {
        model: "mistralai/mistral-7b-instruct:free",
        messages: [
          { role: "user", content: build_contract_prompt(@description) }
        ],
        temperature: 0.8,
        max_tokens: 500
      }.to_json

      response = http.request(request)

      if response.code == "200"
        result = JSON.parse(response.body)
        ai_text = result.dig("choices", 0, "message", "content") ||
                  result.dig("choices", 0, "text")
        return ai_text&.strip
      else
        Rails.logger.error "OpenRouter API error: #{response.code} - #{response.body}"
        return nil
      end
    rescue => e
      Rails.logger.error "OpenRouter API call failed: #{e.message}"
      return nil
    end
  end

  def generate_with_smart_template
    Rails.logger.info "Generating with smart template"
    
    # Extract entities from description
    entities = extract_entities(@description)
    contract_type = determine_contract_type(@description)
    
    case contract_type
    when 'collaboration'
      generate_collaboration_contract(entities)
    when 'partnership'
      generate_partnership_contract(entities)
    when 'service'
      generate_service_contract(entities)
    when 'employment'
      generate_employment_contract(entities)
    when 'nda'
      generate_nda_contract(entities)
    else
      generate_general_contract(entities)
    end
  end

  def build_contract_prompt(description)
    "Please generate a professional contract based on the following description: #{description}. 
    
    The contract should include:
    - Proper legal structure with parties, scope, terms, and conditions
    - Clear deliverables and timelines if applicable
    - Payment terms if mentioned
    - Proper legal clauses for termination, confidentiality, and governing law
    - Professional formatting with sections and subsections
    
    Make sure the contract is complete and ready to use."
  end

  def extract_entities(description)
    entities = {}
    
    # Extract potential party names (proper nouns)
    words = description.split
    proper_nouns = words.select { |word| word =~ /^[A-Z][a-z]+/ }
    
    entities[:party1] = proper_nouns[0] if proper_nouns[0]
    entities[:party2] = proper_nouns[1] if proper_nouns[1]
    
    # Extract dollar amounts
    if description =~ /\$?(\d+(?:,\d{3})*(?:\.\d{2})?)\s*dollars?/i
      entities[:amount] = "$#{$1}"
    elsif description =~ /(\d+)\s*dollars?/i
      entities[:amount] = "$#{$1}"
    end
    
    # Extract time periods
    if description =~ /(\d+)\s*weeks?/i
      entities[:duration] = "#{$1} week(s)"
    elsif description =~ /(\d+)\s*months?/i
      entities[:duration] = "#{$1} month(s)"
    elsif description =~ /(\d+)\s*days?/i
      entities[:duration] = "#{$1} day(s)"
    end
    
    # Extract deliverables count
    if description =~ /(\d+)\s*videos?/i
      entities[:video_count] = $1
      entities[:content_type] = "video"
    elsif description =~ /(\d+)\s*posts?/i
      entities[:post_count] = $1
      entities[:content_type] = "post"
    end
    
    entities
  end

  def determine_contract_type(description)
    desc_lower = description.downcase
    
    return 'collaboration' if desc_lower.include?('collaboration') || desc_lower.include?('collab')
    return 'partnership' if desc_lower.include?('partnership') || desc_lower.include?('partner')
    return 'service' if desc_lower.include?('service') || desc_lower.include?('work')
    return 'employment' if desc_lower.include?('employment') || desc_lower.include?('job')
    return 'nda' if desc_lower.include?('nda') || desc_lower.include?('non-disclosure')
    
    'general'
  end

  def generate_collaboration_contract(entities)
    <<~CONTRACT
      **COLLABORATION AGREEMENT**

      This Collaboration Agreement ("Agreement") is made and entered into on **[Date]**, by and between:

      **#{entities[:party1] || '[Party 1]'}**, having its principal place of business at [Address], hereinafter referred to as the "Brand",

      **AND**

      **#{entities[:party2] || '[Party 2]'}**, an individual content creator, residing at [Address], hereinafter referred to as the "Influencer".

      Collectively referred to as the "Parties".

      ---

      ## 1. SCOPE OF COLLABORATION

      #{generate_scope_section(entities)}

      ## 2. DELIVERABLES

      #{generate_deliverables_section(entities)}

      ## 3. COMPENSATION

      #{generate_compensation_section(entities)}

      ## 4. TIMELINE

      #{generate_timeline_section(entities)}

      ## 5. CONTENT RIGHTS AND USAGE

      - The Influencer grants the Brand a non-exclusive, royalty-free license to use, repost, and promote the content across digital channels.
      - The Brand may not alter the content without the Influencer's prior consent.

      ## 6. DISCLOSURE AND COMPLIANCE

      - Influencer shall clearly disclose the collaboration in all posts in compliance with applicable guidelines using hashtags such as #Ad, #Sponsored, or as applicable.

      ## 7. CONFIDENTIALITY

      - Both Parties agree to keep the terms of this Agreement confidential unless disclosure is required by law.

      ## 8. TERMINATION

      - Either party may terminate this Agreement with written notice if the other party breaches any material term and fails to remedy within 3 business days.

      ## 9. GOVERNING LAW

      - This Agreement shall be governed by the laws of [Applicable Jurisdiction].

      ---

      **SIGNATURES**

      **For #{entities[:party1] || '[Party 1]'}**
      Name: ________________
      Title: ________________
      Signature: ________________
      Date: ________________

      **For #{entities[:party2] || '[Party 2]'}**
      Name: ________________
      Signature: ________________
      Date: ________________

      ---

      *This contract was generated based on: "#{@description}"*
    CONTRACT
  end

  def generate_general_contract(entities)
    <<~CONTRACT
      **CONTRACT AGREEMENT**

      This Agreement is made and entered into on **[Date]**, by and between:

      **#{entities[:party1] || '[Party 1]'}** and **#{entities[:party2] || '[Party 2]'}**

      ## 1. DESCRIPTION

      #{@description}

      ## 2. TERMS AND CONDITIONS

      #{generate_terms_section(entities)}

      ## 3. PAYMENT

      #{generate_payment_section(entities)}

      ## 4. TIMELINE

      #{generate_timeline_section(entities)}

      ## 5. LEGAL PROVISIONS

      - **Governing Law:** This Agreement shall be governed by applicable laws.
      - **Termination:** Either party may terminate with appropriate notice.
      - **Confidentiality:** Both parties agree to maintain confidentiality of sensitive information.

      ## 6. SIGNATURES

      **#{entities[:party1] || '[Party 1]'}**
      Name: ________________
      Signature: ________________
      Date: ________________

      **#{entities[:party2] || '[Party 2]'}**
      Name: ________________
      Signature: ________________
      Date: ________________

      ---

      *This contract was generated based on: "#{@description}"*
    CONTRACT
  end

  def generate_scope_section(entities)
    if entities[:content_type] && entities[:video_count]
      "The Brand engages the Influencer to create and publish **#{entities[:video_count]} #{entities[:content_type]} content posts** on the Influencer's social media platforms#{entities[:duration] ? " over a period of **#{entities[:duration]}**" : ""}."
    else
      "The parties agree to collaborate as described in the original request: #{@description}"
    end
  end

  def generate_deliverables_section(entities)
    if entities[:video_count] && entities[:content_type]
      <<~DELIVERABLES
        - Influencer shall create **#{entities[:video_count]} original #{entities[:content_type]} posts** as specified.
        - Content shall be posted on platforms agreed by both parties (e.g., Instagram, YouTube, TikTok, etc.).
        - Content shall remain live for a minimum of **30 days** post-publication.
      DELIVERABLES
    else
      "- Deliverables shall be as specified in the original description: #{@description}"
    end
  end

  def generate_compensation_section(entities)
    if entities[:amount]
      <<~COMPENSATION
        - The Brand agrees to pay the Influencer a total of **#{entities[:amount]}** for the services described above.
        - Payment will be made **within 5 business days** after completion of the campaign and submission of all deliverables.
      COMPENSATION
    else
      "- Compensation shall be as specified in the original description: #{@description}"
    end
  end

  def generate_timeline_section(entities)
    if entities[:duration]
      <<~TIMELINE
        - Campaign duration: **#{entities[:duration]}** starting from **[Start Date]** to **[End Date]**.
        - Posting schedule to be mutually agreed upon before the start of the campaign.
      TIMELINE
    else
      "- Timeline shall be as specified in the original description: #{@description}"
    end
  end

  def generate_terms_section(entities)
    terms = []
    terms << "Duration: #{entities[:duration]}" if entities[:duration]
    terms << "Payment: #{entities[:amount]}" if entities[:amount]
    terms << "Deliverables: #{entities[:video_count]} #{entities[:content_type]} posts" if entities[:video_count] && entities[:content_type]
    
    if terms.any?
      "- " + terms.join("\n- ")
    else
      "- Terms shall be as specified in the original description: #{@description}"
    end
  end

  def generate_payment_section(entities)
    if entities[:amount]
      "- Total payment: **#{entities[:amount]}**\n- Payment terms: Within 5 business days of completion"
    else
      "- Payment terms shall be as specified in the original description: #{@description}"
    end
  end

  # Additional contract type generators
  def generate_partnership_contract(entities)
    generate_general_contract(entities).gsub("CONTRACT AGREEMENT", "PARTNERSHIP AGREEMENT")
  end

  def generate_service_contract(entities)
    generate_general_contract(entities).gsub("CONTRACT AGREEMENT", "SERVICE AGREEMENT")
  end

  def generate_employment_contract(entities)
    generate_general_contract(entities).gsub("CONTRACT AGREEMENT", "EMPLOYMENT AGREEMENT")
  end

  def generate_nda_contract(entities)
    generate_general_contract(entities).gsub("CONTRACT AGREEMENT", "NON-DISCLOSURE AGREEMENT")
  end
end