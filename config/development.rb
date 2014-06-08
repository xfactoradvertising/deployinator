Deployinator.log_file = Deployinator.root(["log", "development.log"])

Deployinator.domain = 'xfactordevelopment.com'
Deployinator.default_user = "deployinator"

# TODO setup issue tracker integration?
# Deployinator.issue_tracker = proc do |issue|
#   "https://github.com/example/repo/issues/#{issue}"
# end

Deployinator.default_stack = "smart"
Deployinator.protocol = "http"

# TODO configure email (use SES)
# Pony.options = {
#   :via         => :smtp,
#   :from        => "deployinator@#{Deployinator.domain}",
#   :headers     => {"List-ID" => "deploy-announce"},
#   :to          => "joboblee@#{Deployinator.domain}",
#   :via_options => {
#     :address              => 'smtp.gmail.com',
#     :port                 => '587',
#     :enable_starttls_auto => true,
#     :user_name            => 'gmailuser@gmail.com',
#     :password             => 'gmail-password',
#     :authentication       => :plain,
#     :domain               => Deployinator.domain
#   }
# }