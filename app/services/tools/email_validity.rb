module Tools
  class EmailValidity
    include ToolHarness::Tool

    def self.tool_name   = "Email Validity"
    def self.category    = :email
    def self.description = "Validates an email address: format, MX/A deliverability, disposable-domain detection, and a best-effort SMTP mailbox probe (port 25 permitting)."
    def self.form_fields = { email: :text }
    def self.input_type  = :email
    def self.cacheable?  = false
    def self.timeout     = 15

    def execute(params)
      raw = ::EmailValidityChecker.check(params[:email])

      ToolHarness::Result.new(
        success: raw[:success],
        tool: self.class.tool_name,
        data: raw.except(:issues, :success, :error),
        issues: raw[:issues] || [],
        summary: build_summary(raw),
        error: raw[:error]
      )
    end

    private

    def build_summary(raw)
      return "#{raw[:email]} — invalid email format." unless raw[:valid_format]

      parts = ["valid format"]
      parts << if raw[:deliverable]
                 "deliverable#{raw[:mx_hosts].to_a.any? ? " (mx: #{raw[:mx_hosts].first})" : ''}"
               else
                 "not deliverable"
               end
      parts << "disposable" if raw[:disposable]
      parts << "mailbox #{raw[:smtp]}" unless raw[:smtp] == "skipped"
      "#{raw[:email]} — #{parts.join(' · ')}."
    end
  end
end
