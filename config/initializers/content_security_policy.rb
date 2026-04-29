Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src  :self, :nonce           # importmap generates inline <script> tags that need a nonce
    policy.style_src   :self, :unsafe_inline   # Bootstrap + inline style="" attributes used throughout
    policy.img_src     :self, :data
    policy.font_src    :self, :data
    policy.connect_src :self
    policy.object_src  :none
    policy.base_uri    :self
    policy.frame_ancestors :none
    policy.form_action :self
  end

  # Rails attaches this nonce automatically to javascript_importmap_tags,
  # javascript_include_tag, and javascript_tag when script-src is in nonce directives.
  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
