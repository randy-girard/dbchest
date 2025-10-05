namespace :ansible do
  desc "List recent Ansible log files"
  task logs: :environment do
    log_dir = Rails.root.join("log", "ansible")

    if File.directory?(log_dir)
      log_files = Dir.glob(log_dir.join("*.log")).sort_by { |f| File.mtime(f) }.reverse

      if log_files.any?
        puts "Recent Ansible log files (newest first):"
        log_files.first(10).each_with_index do |file, i|
          size = (File.size(file) / 1024.0).round(1)
          mtime = File.mtime(file).strftime("%Y-%m-%d %H:%M:%S")
          puts "  #{i + 1}. #{File.basename(file)} (#{size}KB, #{mtime})"
        end

        puts "\nTo view a log file:"
        puts "  cat log/ansible/#{File.basename(log_files.first)}"
        puts "  tail -f log/ansible/#{File.basename(log_files.first)}"

        puts "\nTo view only errors:"
        puts "  grep -B 2 -A 10 'FAILED\\|Error\\|error\\|fatal' log/ansible/#{File.basename(log_files.first)}"
      else
        puts "No Ansible log files found."
      end
    else
      puts "Ansible log directory not found: #{log_dir}"
    end
  end

  desc "Show errors from the latest Ansible log"
  task errors: :environment do
    log_dir = Rails.root.join("log", "ansible")

    if File.directory?(log_dir)
      log_files = Dir.glob(log_dir.join("*.log")).sort_by { |f| File.mtime(f) }.reverse

      if log_files.any?
        latest_log = log_files.first
        puts "Errors from: #{File.basename(latest_log)}"
        puts "=" * 60

        system("grep -B 2 -A 10 'FAILED\\|Error\\|error\\|fatal' '#{latest_log}'")
      else
        puts "No Ansible log files found."
      end
    else
      puts "Ansible log directory not found."
    end
  end

  desc "Tail the latest Ansible log file"
  task tail: :environment do
    log_dir = Rails.root.join("log", "ansible")

    if File.directory?(log_dir)
      log_files = Dir.glob(log_dir.join("*.log")).sort_by { |f| File.mtime(f) }.reverse

      if log_files.any?
        latest_log = log_files.first
        puts "Tailing: #{File.basename(latest_log)}"
        puts "Press Ctrl+C to stop"
        system("tail -f '#{latest_log}'")
      else
        puts "No Ansible log files found."
      end
    else
      puts "Ansible log directory not found."
    end
  end

  desc "Show logs for a specific node"
  task :node, [ :node_id ] => :environment do |t, args|
    unless args[:node_id]
      puts "Usage: rake ansible:node[NODE_ID]"
      exit 1
    end

    log_dir = Rails.root.join("log", "ansible")

    if File.directory?(log_dir)
      log_files = Dir.glob(log_dir.join("node_#{args[:node_id]}_*.log")).sort_by { |f| File.mtime(f) }.reverse

      if log_files.any?
        puts "Ansible logs for node #{args[:node_id]} (newest first):"
        log_files.each_with_index do |file, i|
          size = (File.size(file) / 1024.0).round(1)
          mtime = File.mtime(file).strftime("%Y-%m-%d %H:%M:%S")
          puts "  #{i + 1}. #{File.basename(file)} (#{size}KB, #{mtime})"
        end

        puts "\nTo view the latest log:"
        puts "  cat '#{log_files.first}'"
      else
        puts "No Ansible log files found for node #{args[:node_id]}."
      end
    else
      puts "Ansible log directory not found."
    end
  end
end
