# Ara VLSU lab
Codespaces Linux üzerinde iki lane ile unmasked VLE32 ve VSE32 testi.

1. Bu dizinin içeriğini repo köküne yerleştir. GitHub'da Makefile ile birlikte .devcontainer/Dockerfile ve .devcontainer/devcontainer.json göründüğünü kontrol et.
2. Code → Codespaces → Create codespace on main. İlk açılışta Debian ortamına Verilator kurulur.
3. Terminalde `make sim` çalıştır. Beklenen son mesaj `PASS: VLE32 -> lane 0/1 -> VSE32; dst = 10, 20, 30, 40`.
4. Explorer'da build/vlsu_load_store.fst dosyasını aç. Gerekiyorsa Open With → Surfer kullan. Alternatif olarak dosyayı indirip https://app.surfer-project.org/ içinde aç.
5. İlk inceleme için tb_vlsu altında clk_i, pe_req_valid_i, addrgen_ack_o ve ar_fire sinyallerini seç. dut/i_addrgen altında axi_addrgen_state_q ve axi_ar_valid_o sinyallerini ekle. 40–75 ns aralığı ilk LOAD'un adres aşamasıdır.

DUT rtl/vlsu.sv; testbench tb/tb_vlsu.sv. Kaynak dizinlerinde gerçek RTL, yardımcı modüller ve package tanımları bulunur. Sürüm Ara 34bd3bc152421b4601a7bf3d6e8e91ffb545c99e. Yeniden koşmak için yine make sim kullan.
