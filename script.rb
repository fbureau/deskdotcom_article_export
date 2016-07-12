### CONFIGURATION
#################

# CONNECTION
TOKEN           = ''
TOKEN_SECRET    = ''
CONSUMER_KEY    = ''
CONSUMER_SECRET = ''
ENDPOINT      = 'https://example.desk.com'

# OTHER
FOLDER_NAME       = './export'
MASTER_LANGUAGE   = 'fr'
SUMMARY_FIELD     = 'body__c'
DESCRIPTION_FIELD = 'description__c'
CHANNELS          = 'application+sites+csp'

# CSV SETTINGS
DATE_FORMAT       = 'yyyy-MM-dd'
DATE_TIME_FORMAT  = 'yyyy-MM-dd HH:mm:ss'
CSV_ENCODING      = Encoding::default_external.to_s # UTF-8
CSV_SEPARATOR     = ','
RTA_ENCODING      = Encoding::default_external.to_s # UTF-8

### SCRIPT - DON'T TOUCH
######################
require 'desk_api'
require 'open_uri_redirections'
require 'csv'
require 'rails-html-sanitizer'

full_sanitizer = Rails::Html::FullSanitizer.new

# create the file system
Dir.mkdir File.expand_path(FOLDER_NAME) unless Dir.exists?(File.expand_path(FOLDER_NAME))
['data', 'data/images'].each do |dir|
  Dir.mkdir("#{File.expand_path(FOLDER_NAME)}/#{dir}") unless Dir.exists?("#{File.expand_path(FOLDER_NAME)}/#{dir}")
end

# create the csv file
CSV.open("#{File.expand_path(FOLDER_NAME)}/articles.csv", 'wb', {
  col_sep: CSV_SEPARATOR,
  encoding: CSV_ENCODING
}) do |csv|
  # write the properties file
  File.open("#{File.expand_path(FOLDER_NAME)}/articles.properties", 'wb') do |file|
    file.write [
      "DateFormat=#{DATE_FORMAT}",
      "DateTimeFormat=#{DATE_TIME_FORMAT}",
      "CSVEncoding=#{CSV_ENCODING}",
      "CSVSeparator=#{CSV_SEPARATOR}",
      "RTAEncoding=#{RTA_ENCODING}"
    ].join("\n")
  end

  # write the headers
  csv << ['isMaster Language', 'In support center', 'Title', 'Body', 'File name', 'Category', 'Channels', 'Language', 'quickcode']

  # get the topics
  topics = DeskApi::Client.new({
    token:            TOKEN,
    token_secret:     TOKEN_SECRET,
    consumer_key:     CONSUMER_KEY,
    consumer_secret:  CONSUMER_SECRET,
    endpoint:         ENDPOINT
  }).topics

  begin
    # run through the topics
    topics.entries.each do |topic|
      next unless topic.in_support_center

      # fetch the articles
      articles = topic.articles

      begin
        # run through the articles
        articles.entries.each do |article|
          next unless article.in_support_center

          # fetch the translations
          translations = article.translations

          begin
            # run through the translations
            translations.entries.each do |translation|
              is_master   = translation.locale.downcase == MASTER_LANGUAGE.downcase
              file_name   = "data/#{article.href[/\d+$/]}_#{translation.locale}.html"
              img_folder  = "images/#{article.href[/\d+$/]}_#{translation.locale}"

              # add the article to the csv
              csv << [
                is_master ? 1 : 0,
                article.in_support_center,
                translation.subject,
                full_sanitizer.sanitize(translation.body),
                file_name,
                is_master ? topic.name : '',
                is_master ? CHANNELS : '',
                translation.locale,
                article.quickcode
              ]

              # create an image folder for this article
              Dir.mkdir("#{File.expand_path(FOLDER_NAME)}/data/#{img_folder}") rescue 0

              # write the article
              File.open("#{File.expand_path(FOLDER_NAME)}/#{file_name}", 'wb') do |file|
                # extract images and save
                body = translation.body.tap do |content|
                  content.scan(/<img[^>]+src="([^">]+)"/).each do |image|
                    begin
                      # build the uri
                      image_uri = URI::parse(image.first)
                      image_uri.scheme = 'https' unless image_uri.scheme
                      image_uri.host   = URI::parse(ENDPOINT).host unless image_uri.host

                      # get the name
                      image_name = File.basename(image_uri.path)

                      # download the file
                      File.open("#{File.expand_path(FOLDER_NAME)}/data/#{img_folder}/#{image_name}", 'wb') do |file|
                        file.print open(image_uri.to_s, allow_redirections: :all).read
                      end

                      # change the image src to the new path
                      content[image.first] = "#{img_folder}/#{image_name}"
                    rescue
                    end
                  end
                end

                file.write body
              end

              # delete image folder if empty
              Dir.delete("#{File.expand_path(FOLDER_NAME)}/data/#{img_folder}") rescue 0
            end

          end while translations = translations.next
        end

      end while articles = articles.next
    end

  end while topics = topics.next
end