capybara-scraper
================

Запустить 'ruby scraper.rb 100..103-04-2014',

ruby scraper.rb 100-03-2015
ruby scraper.rb 102-03-2015
ruby scraper.rb 104-03-2015

где 100..103 - интервал значений в строке https://eecology.espesoft.com:8443/ecologyapp/showRegisteredUser
04 - квартал
2014 - год

Удалить черный список организаций:
rm -r existing_orgs.txt

Не забудь почистить куки и историю браузера перед запуском, вообще всю
