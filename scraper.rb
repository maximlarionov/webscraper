#!/usr/bin/env ruby
require "rubygems"
require "rails"
require "rubyXL"
require "bundler/setup"
require "capybara"
require "capybara/dsl"
require "capybara-webkit"
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

    def get_results(page)
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

      @data_array

      @final_array_item += ["Название", "ИНН", "КПП", "Рег Номер", "Телефон", "Адрес", "Логин", "Пароль", "Сумма"]

      @final_array << @final_array_item

      # remove useless 1'st element from @data_array
      @data_array.shift

      # processing elements from @data_array
      @data_array.first(20).each do |element|
        begin
          process_single_element(element)
        rescue Capybara::Webkit::NodeNotAttachedError, Capybara::ElementNotFound
          @final_array << @final_array_item
        end
      end

      @final_array
    end

    def process_single_element(data_element)
      # сразу заполняем название, инн, кпп и рег номер в таблицу
      @final_array_item = data_element.first(4)

      puts @final_array_item.to_s

      if data_element.first(4).any?(&:blank?)
        @final_array_item << "ИНН, КПП или Рег номер не указаны"
        @final_array_item << "/n /n"
        raise Capybara::ElementNotFound
      end

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

      # Если ИП - клик по ИП
      if data_element[0].include?("И.П")
        raschet_table[0].click
      end

      # Забиваем ИНН, КПП, Рег номер соответствующими полями
      raschet_table[1].set(data_element[1])
      raschet_table[2].set(data_element[2])
      raschet_table[3].set(data_element[3])

      click_on "Принять"
      wait_for_ajax

      # Выбираем 4 квартал
      find("#selectQuarter").select("4 квартал")

      # 2014 год
      find("#selectYear").select("2014")

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
      sleep 10

      if page.body.include?("Данные Росприроднадзора")
        @final_array_item << "Некорректно указаны персональные данные"
        @final_array_item << "/n /n"
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
      @final_array_item << "Общая сумма: #{find('#declarationSumAll').text}"

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
        # название площадки
        ploshadka_array << "Площадка: #{ploshadka.text}"

        list = find("ul#accordion")
        elements = list.all("li")
        all_element_array = []

        elements.each_with_index do |element, index|
          element_string = ""
          element.click

          wait_for_ajax

          element_string += "Раздел #{index + 1}, "
          #cроки
          if element.first("p")
            element_string += "Срок: #{element.first('p').text}, "
          else
            element_string += "Срок: нет, "
          end

          #сумма
          summa = element.all("strong").select { |t| t.text != "0" }.last(2).uniq.last
          if summa != nil && summa.text.to_f != 0.0
            sum = "Сумма: #{summa.text}"
          else
            sum = "Сумма: нет"
          end

          element_string += sum

          # заполняем и обнуляем массив
          all_element_array << element_string
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

ARGV.each do |arg|
  result = spider.get_results(arg.to_i)

  worksheet = workbook.add_worksheet("стр #{100-arg.to_i}")

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

workbook.write("organizations.xlsx")

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
