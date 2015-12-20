# encoding: UTF-8
#!/usr/bin/env ruby
require "rubygems"
require "rails"
require "rubyXL"
require "bundler/setup"
require "capybara"
require "capybara/dsl"
require "selenium-webdriver"
require "pry"
require "pry-byebug"
require "spreadsheet"

Capybara.run_server = false
Capybara.current_driver = :selenium
Capybara.app_host = "http://www.google.com/"

module WaitForAjax
  def wait_for_ajax
    Timeout.timeout(20) do
      loop until finished_all_ajax_requests?
    end
  end

  def finished_all_ajax_requests?
    page.evaluate_script('jQuery.active').zero?
  end
end

module Test
  class Google
    include Capybara::DSL
    include WaitForAjax

    def bisection_between(data_array)
      unless File.exists?('existing_orgs.txt')
        `touch existing_orgs.txt`
      end

      existing_orgs = File.readlines("existing_orgs.txt").map { |el| el.gsub("\n", "") }

      new_data_array = []
      new_data_reg_nums = []

      data_array.each do |element|
        if !existing_orgs.include? element[3]
          new_data_array << element
          new_data_reg_nums << element[3]
        end
      end

      new_existing_orgs = existing_orgs + new_data_reg_nums

      File.truncate('existing_orgs.txt', 0)
      File.open("existing_orgs.txt", "w") do |f|
        new_existing_orgs.each do |row|
          f << row
          f << "\n"
        end
      end

      new_data_array
    end

    def get_results(page, kvartal, year)
      visit "https://eecology.espesoft.com:8443/ecologyapp/showRegisteredUser"

      find("td #searchTextField").set(page)

      click_button "Найти"

      @final_array = []
      @final_array_item = []
      @data_array = []
      data_element = []

      results_table = find("#resultSearchUserTable")

      results_table.all("tr").each do |row|
        row.all("td").each do |cell|
          data_element << cell.text
        end

        @data_array << data_element
        data_element = []
      end

      @final_array_item += ["Название", "ИНН", "КПП", "Рег Номер", "Телефон", "Адрес", "Логин", "Пароль", "Общая сумма"]

      @final_array << @final_array_item

      # remove useless 1'st element from @data_array
      @data_array.shift

      # remove already existing orgs from data array
      @data_array = bisection_between(@data_array)

      # processing elements from @data_array
      @data_array.each do |element|
        begin
          process_single_element(element, kvartal, year)
        rescue Capybara::ElementNotFound, Selenium::WebDriver::Error::JavascriptError
          @final_array << "\n\n"
          next
        end
      end

      @final_array
    end

    def process_single_element(data_element, kvartal, year)
      # сразу заполняем название, инн, кпп и рег номер в таблицу
      data_element = ["ООО \"БИ КОМПАНИ-СЕРВИС\"", "1644016837", "164401001", "010201494"]
      @final_array_item = data_element.first(4)

      puts @final_array_item.to_s

      visit "https://eecology.espesoft.com/ecologyapp/public/mainPage.action"

      wait_for_ajax

      # расчет платы
      find("#buttonSet").all(".eebtn").first.click

      # coздать новый
      find(".regLink").click

      # таблица с полями
      find(".tableNew")

      # вводим данные
      raschet_table = find(".tableNew").all("input")

      # Если ИП или ЧП - клик по ИП
      if data_element[0].slice(0..4).include?("ИП" || "ЧП" || "Инди" || "Част" || "И.П" || "Ч.П")
        raschet_table[0].click
        wait_for_ajax
        raschet_table[1].set(data_element[1])
        raschet_table[3].set(data_element[3])
      else
      # Забиваем ИНН, КПП, Рег номер соответствующими полями
        raschet_table[1].set(data_element[1])
        raschet_table[2].set(data_element[2])
        raschet_table[3].set(data_element[3])
      end

      click_on "Принять"
      wait_for_ajax

      # Выбираем нужный квартал
      find("#selectQuarter").select("#{kvartal} квартал")

      # 2014 год
      find("#selectYear").select("#{year}")

      # Выбираем корректирующий
      find("#selectDocType").select("Корректирующий")

      # заполняем нужные поля
      # телефон
      @final_array_item << page.all("input").map(&:value)[9]
      # адрес
      @final_array_item << page.first("textarea").text

      # создаем расчет
      click_on("Создать расчет платы")

      # надо подождать, пока заполнится таблица, она чот долго грузится :(((
      wait_for_ajax

      while first("#loadingText") != nil do
        sleep 2
      end

      if page.body.include?("Данные Росприроднадзора")
        puts "Некорректно указаны персональные данные"
        raise Capybara::ElementNotFound
      end
      # подтверждаем алерт, просто так.
      click_button "Принять"

      # заполняем логин и пароль этим хуеселектором
      @final_array_item += page.first("td.fontGreen").text.split(/[^\d]/).join(" ").split(" ")

# __________ все что выше - работает. Все данные до адреса и телефона включительно
# __________ down here is needed to rework a little bit __________

      # метод для обработки разделов
      # find("ul#accordion").all("li").first.click
      wait_for_ajax

      vse_promploshadki_array = parse_razdels

      wait_for_ajax
      @final_array_item << find('#declarationSumAll').text

      # получили данные со всех промлощадок одного элемента
      # записали в конечный массив и обнулили

      # записываем в итоговый массив
      @final_array << @final_array_item

      vse_promploshadki_array.each do |ploshadka|
        @final_array << ploshadka
      end
      @final_array_item = []
      vse_promploshadki_array = []

      # выходим из расчета и начинаем как другой юзер
      @final_array << "\n\n"
      Capybara.reset_sessions!
    end

    def parse_razdels
      # находим дропдаун со всеми элементами
      dropdown_dlya_promploshadok = find("#areaTemp")
      vse_promploshadki = dropdown_dlya_promploshadok.all("option")

      vse_promploshadki_array = []
      ploshadka_array = []

      vse_promploshadki.each do |ploshadka|
        dropdown_dlya_promploshadok.select(ploshadka.text)

        # wait_for_ajax

        # какую-то фигню принять надо
        if page.body.include?("Принять")
          click_button "Принять"
        end

        # название площадки
        ploshadka_array << "Площадка: #{ploshadka.text}"

        list = find("ul#accordion")
        elements = list.all("li")
        all_element_array = []

        elements.each_with_index do |element, index|
          element_array = []
          element.click

          wait_for_ajax

          element_array << "Раздел #{index + 1}"
          #cроки

          if element.first("p")
            date_pattern = /(\d{2})\.(\d{2})\.(\d{4})/
            msg = element.first('p').text

            element_array << "С: #{msg.slice! date_pattern}"
            element_array << "До: #{msg.slice! date_pattern}"
          else
            element_array << "С: --"
            element_array << "До: --"
          end

          #сумма
          summa = element.all("strong").select { |t| t.text != "0" }.last(2).uniq.last
          if summa != nil && summa.text.to_f != 0.0
            sum = "Сумма: #{summa.text}"
          else
            sum = "Сумма: --"
          end

          element_array << sum

          # заполняем и обнуляем массив
          all_element_array << element_array
          element_array = []

          sleep 1
        end


        ploshadka_array += all_element_array
        vse_promploshadki_array += ploshadka_array

        ploshadka_array = []
        all_element_array = []
      end

      vse_promploshadki_array
    end
  end
end

spider = Test::Google.new
workbook = RubyXL::Workbook.new
workbook.worksheets.pop

args = ARGV[0].split("-")
ranges = []

if ARGV[0].include?("..")
  ranges = Range.new(*args[0].split("..").map(&:to_i))
else
  ranges = [args[0].to_i]
end

ranges.each do |arg|
  kvartal = args[1].to_i
  year = args[2].to_i
  result = spider.get_results(arg, kvartal, year)

  worksheet = workbook.add_worksheet("стр:#{arg}, квт:#{kvartal}, год:#{year}")

  result.each_with_index do |row, row_id|
    if result[row_id].instance_of?(Array)
      row.each_with_index do |cell, cell_id|
        worksheet.add_cell(row_id, cell_id, result[row_id][cell_id])
      end
    else
      worksheet.add_cell(row_id, 0, result[row_id])
    end
  end
end

workbook.write("(#{Time.now.strftime("%d %h, %Y %H:%M")}) - организации.xlsx")

# to txt
# ARGV.each do |arg|
#   result = spider.get_results(arg.to_i)

#   print_result = []

#   result.each do |row|
#     if row.instance_of?(Array)
#       row = row.join("  |  ")
#       print_result.push row
#     else
#       print_result.push row
#     end
#   end

#   print = print_result.join("\n")

#   File.open("#{arg}-output.txt", "w") { |file| file.write print }
# end
