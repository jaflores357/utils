#!/opt/chef/embedded/bin/ruby

# Global constants
MYSQL_HOST = "<DBHOST>"
MYSQL_USER = "<DBUSER"
MYSQL_PASS = "<DBPASS>"

# Pager duty
SERVICE_KEY = '<SERVICE_KEY>'
ENDPOINT = 'https://events.pagerduty.com/v2/enqueue'
PD_DESCRIPTION = "Project - Copy ERRORS"

# Required gems
require "mysql"
require "httparty"


error = 'resolve'
error_desc = []
begin
  # Connection with database
  con1 = Mysql.new(MYSQL_HOST, MYSQL_USER, MYSQL_PASS)
  # Select database
  con1.select_db("DBNAME")

  query="SELECT 
  IFNULL((SELECT GROUP_CONCAT(j.jobname) JOBS 
  FROM (
      SELECT jobname 
      FROM purebros.tab_dw_copy_run_board b 
      NATURAL JOIN purebros.tab_dw_copy_jobs j 
      WHERE executiontimestamp >= CURRENT_DATE 
      AND JobSystem = 'PROD' 
      AND STATUS IN ('ERROR','LACK_OF_PREREQ','VERIFIER_ERROR') 
      -- AND STATUS IN ('SUCCESS' )
      AND JobStatus = 'ENABLE' 
      -- AND JobIsPriority = 1 
      LIMIT 3) j
  ),'none') 'Errors'"

  # Fetch list
  rs = con1.query(query)
  
  rs.each_hash do |row|
    if row['Errors'] != "none"
        error = 'trigger' 
        error_desc << row['Errors']
    end
  end

  # Close connection
  con1.close

rescue
  puts "ERROR: Exception when running queries"
  puts $!, $@
  exit 1
end


if error

  data = {
    "routing_key": "#{SERVICE_KEY}",
    "event_action": error,
    "dedup_key": 'CopyErrors',
    "payload": {
      "summary": "#{PD_DESCRIPTION}", 
      "severity": "critical", 
      "source": "api",
      "custom_details": {
        "Jobs": error_desc.uniq
      }
    }
  }

  response = HTTParty.post(
    ENDPOINT,
    body: data.to_json,
    headers: {
      'Content-Type' => 'application/json'
    }
  )
  puts "Pager Duty response: #{response.body}"
  exit 1
else
  exit 0
end
