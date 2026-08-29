#!/usr/bin/env python3
"""Build the on-device essential medication catalog (JSON). Not a live world dump."""

from __future__ import annotations

import json
from pathlib import Path

# name, aliases, optional form, optional strength
RAW: list[tuple[str, list[str], str, str]] = []


def add(name: str, aliases: list[str] | None = None, form: str = "", strength: str = "") -> None:
    RAW.append((name, aliases or [], form, strength))


# --- Brazil / LATAM essentials + INN + common brands ---
add("Dipirona", ["Metamizole", "Dipyrone", "Novalgina", "Novalgin", "Anador", "Magnopyrol"], "tablet / drops", "500 mg")
add("Metamizole", ["Dipirona", "Dipyrone", "Novalgina"], "tablet", "500 mg")
add("Amoxicilina", ["Amoxicillin", "Amoxil", "Amoxilina"], "capsule / syrup", "500 mg")
add("Amoxicillin", ["Amoxicilina", "Amoxil"], "capsule", "500 mg")
add("Amoxicilina + Clavulanato", ["Amoxicillin clavulanate", "Clavulin", "Augmentin", "Amoxi-clav"], "tablet / syrup", "875/125 mg")
add("Azitromicina", ["Azithromycin", "Zitromax", "Zithromax"], "tablet / syrup", "500 mg")
add("Azithromycin", ["Azitromicina", "Zithromax"], "tablet", "500 mg")
add("Cefalexina", ["Cephalexin", "Keflex", "Cefalexin"], "capsule", "500 mg")
add("Ceftriaxona", ["Ceftriaxone", "Rocefin"], "injection", "1 g")
add("Ciprofloxacino", ["Ciprofloxacin", "Cipro"], "tablet", "500 mg")
add("Levofloxacino", ["Levofloxacin", "Levaquin", "Tavanic"], "tablet", "500 mg")
add("Sulfametoxazol + Trimetoprima", ["Cotrimoxazole", "Bactrim", "Septrin", "SMX-TMP"], "tablet", "400/80 mg")
add("Nitrofurantoína", ["Nitrofurantoin", "Macrodantin", "Macrobid"], "capsule", "100 mg")
add("Metronidazol", ["Metronidazole", "Flagyl"], "tablet", "400 mg")
add("Doxiciclina", ["Doxycycline", "Vibramycin"], "capsule", "100 mg")
add("Clindamicina", ["Clindamycin", "Dalacin"], "capsule", "300 mg")
add("Fluconazol", ["Fluconazole", "Zoltec", "Diflucan"], "capsule", "150 mg")
add("Nistatina", ["Nystatin", "Mycostatin"], "oral suspension", "")
add("Aciclovir", ["Acyclovir", "Zovirax"], "tablet", "400 mg")
add("Oseltamivir", ["Tamiflu"], "capsule", "75 mg")
add("Ivermectina", ["Ivermectin", "Revectina"], "tablet", "6 mg")
add("Albendazol", ["Albendazole", "Zentel"], "tablet", "400 mg")
add("Mebendazol", ["Mebendazole", "Pantelmin"], "tablet", "100 mg")

add("Ibuprofeno", ["Ibuprofen", "Advil", "Motrin", "Alivium", "Buscofen"], "tablet / suspension", "400 mg")
add("Ibuprofen", ["Ibuprofeno", "Advil", "Motrin"], "tablet", "400 mg")
add("Paracetamol", ["Acetaminophen", "Tylenol", "Dôrico", "Panadol"], "tablet / syrup", "750 mg")
add("Acetaminophen", ["Paracetamol", "Tylenol"], "tablet", "500 mg")
add("Ácido acetilsalicílico", ["Aspirin", "AAS", "Aspirina", "ASA"], "tablet", "100 mg")
add("Aspirin", ["AAS", "Aspirina", "Ácido acetilsalicílico"], "tablet", "100 mg")
add("Nimesulida", ["Nimesulide", "Nisulid", "Scaflam"], "tablet", "100 mg")
add("Diclofenaco", ["Diclofenac", "Cataflam", "Voltaren"], "tablet / gel", "50 mg")
add("Naproxeno", ["Naproxen", "Flanax", "Naprosyn"], "tablet", "500 mg")
add("Cetoprofeno", ["Ketoprofen", "Profénid", "Profenid"], "tablet", "100 mg")
add("Piroxicam", ["Feldene"], "capsule", "20 mg")
add("Meloxicam", ["Mobic", "Movatec"], "tablet", "15 mg")
add("Celecoxibe", ["Celecoxib", "Celebra", "Celebrex"], "capsule", "200 mg")
add("Dipirona + Cafeína", ["Dorflex", "Novalgina composed"], "tablet", "")
add("Orfenadrina", ["Orphenadrine", "Dorflex", "Norflex"], "tablet", "")
add("Codeína", ["Codeine", "Tylex"], "tablet", "30 mg")
add("Tramadol", ["Tramal", "Ultram"], "capsule", "50 mg")
add("Morfina", ["Morphine"], "tablet / injection", "")
add("Dipirona magnésica", ["Magnopyrol"], "drops", "")

add("Prednisona", ["Prednisone", "Meticorten"], "tablet", "20 mg")
add("Prednisone", ["Prednisona", "Meticorten"], "tablet", "20 mg")
add("Prednisolona", ["Prednisolone", "Prelone"], "syrup", "")
add("Dexametasona", ["Dexamethasone", "Decadron"], "tablet / drops", "4 mg")
add("Hidrocortisona", ["Hydrocortisone"], "cream / tablet", "")
add("Betametasona", ["Betamethasone", "Diprospan", "Celestone"], "cream / injection", "")
add("Budesonida", ["Budesonide", "Budecort", "Pulmicort"], "inhaler / nasal", "")
add("Beclometasona", ["Beclomethasone", "Clenil"], "inhaler", "")
add("Fluticasona", ["Fluticasone", "Fluticaps", "Flonase"], "inhaler / nasal", "")
add("Mometasona", ["Mometasone", "Nasonex"], "nasal spray", "")

add("Losartana", ["Losartan", "Cozaar", "Aradois", "Valtrian"], "tablet", "50 mg")
add("Losartan", ["Losartana", "Cozaar"], "tablet", "50 mg")
add("Losartana + Hidroclorotiazida", ["Losartan HCTZ", "Hyzaar", "Aradois H"], "tablet", "50/12.5 mg")
add("Enalapril", ["Renitec", "Vasotec"], "tablet", "10 mg")
add("Captopril", ["Capoten"], "tablet", "25 mg")
add("Ramipril", ["Tritace", "Altace"], "tablet", "5 mg")
add("Lisinopril", ["Zestril", "Prinivil"], "tablet", "10 mg")
add("Valsartana", ["Valsartan", "Diovan"], "tablet", "160 mg")
add("Olmesartana", ["Olmesartan", "Benicar", "Olmetec"], "tablet", "20 mg")
add("Telmisartana", ["Telmisartan", "Micardis"], "tablet", "40 mg")
add("Candesartana", ["Candesartan", "Atacand", "Blopress"], "tablet", "8 mg")
add("Anlodipino", ["Amlodipine", "Norvasc", "Amlocor"], "tablet", "5 mg")
add("Amlodipine", ["Anlodipino", "Norvasc"], "tablet", "5 mg")
add("Nifedipino", ["Nifedipine", "Adalat"], "tablet", "20 mg")
add("Verapamil", ["Dilacoron", "Isoptin"], "tablet", "80 mg")
add("Diltiazem", ["Cardizem"], "tablet", "60 mg")
add("Atenolol", ["Tenormin", "Atenol"], "tablet", "50 mg")
add("Propranolol", ["Inderal"], "tablet", "40 mg")
add("Metoprolol", ["Seloken", "Selozok", "Lopressor", "Toprol"], "tablet", "50 mg")
add("Bisoprolol", ["Concor"], "tablet", "5 mg")
add("Carvedilol", ["Coreg", "Cardilol", "Karvedilol"], "tablet", "12.5 mg")
add("Nebivolol", ["Nebilet"], "tablet", "5 mg")
add("Hidroclorotiazida", ["Hydrochlorothiazide", "HCTZ", "Clorana"], "tablet", "25 mg")
add("Furosemida", ["Furosemide", "Lasix"], "tablet", "40 mg")
add("Espironolactona", ["Spironolactone", "Aldactone"], "tablet", "25 mg")
add("Clortalidona", ["Chlorthalidone", "Higroton"], "tablet", "25 mg")
add("Indapamida", ["Indapamide", "Natrilix"], "tablet", "1.5 mg")
add("Sinvastatina", ["Simvastatin", "Zocor", "Sinvascor"], "tablet", "20 mg")
add("Atorvastatina", ["Atorvastatin", "Lipitor", "Citalor"], "tablet", "20 mg")
add("Rosuvastatina", ["Rosuvastatin", "Crestor"], "tablet", "10 mg")
add("Pravastatina", ["Pravastatin", "Pravachol"], "tablet", "40 mg")
add("Ezetimiba", ["Ezetimibe", "Ezetrol", "Zetia"], "tablet", "10 mg")
add("Fenofibrato", ["Fenofibrate", "Lipanthyl"], "capsule", "160 mg")
add("Sinvastatina + Ezetimiba", ["Vytorin"], "tablet", "")

add("Omeprazol", ["Omeprazole", "Losec", "Prilosec", "Ozemp"], "capsule", "20 mg")
add("Omeprazole", ["Omeprazol", "Prilosec"], "capsule", "20 mg")
add("Pantoprazol", ["Pantoprazole", "Pantozol", "Protonix", "Zurcal"], "tablet", "40 mg")
add("Lansoprazol", ["Lansoprazole", "Prevacid", "Lanzol"], "capsule", "30 mg")
add("Esomeprazol", ["Esomeprazole", "Nexium"], "tablet", "40 mg")
add("Rabeprazol", ["Rabeprazole", "Pariet"], "tablet", "20 mg")
add("Ranitidina", ["Ranitidine", "Zantac", "Label"], "tablet", "150 mg")
add("Famotidina", ["Famotidine", "Pepcid"], "tablet", "20 mg")
add("Domperidona", ["Domperidone", "Motilium", "Peridal"], "tablet", "10 mg")
add("Metoclopramida", ["Metoclopramide", "Plasil", "Reglan"], "tablet / drops", "10 mg")
add("Ondansetrona", ["Ondansetron", "Zofran", "Vonau"], "tablet", "8 mg")
add("Dimenidrinato", ["Dimenhydrinate", "Dramamine", "Dramin"], "tablet", "50 mg")
add("Escopolamina", ["Hyoscine", "Buscopan", "Butylscopolamine"], "tablet", "10 mg")
add("Simeticona", ["Simethicone", "Luftal", "Gascon"], "drops", "")
add("Lactulose", ["Lactulona", "Duphalac"], "syrup", "")
add("Macrogol", ["Polyethylene glycol", "Muvinlax", "MiraLAX"], "powder", "")
add("Loperamida", ["Loperamide", "Imosec", "Imodium"], "tablet", "2 mg")
add("Sulfassalazina", ["Sulfasalazine", "Azulfidine"], "tablet", "500 mg")
add("Mesalazina", ["Mesalamine", "Pentasa", "Asacol"], "tablet", "800 mg")

add("Metformina", ["Metformin", "Glifage", "Glucophage"], "tablet", "850 mg")
add("Metformin", ["Metformina", "Glucophage", "Glifage"], "tablet", "500 mg")
add("Glibenclamida", ["Glyburide", "Glibenclamide", "Daonil"], "tablet", "5 mg")
add("Gliclazida", ["Gliclazide", "Diamicron"], "tablet", "30 mg")
add("Glimepirida", ["Glimepiride", "Amaryl"], "tablet", "2 mg")
add("Sitagliptina", ["Sitagliptin", "Januvia"], "tablet", "100 mg")
add("Vildagliptina", ["Vildagliptin", "Galvus"], "tablet", "50 mg")
add("Empagliflozina", ["Empagliflozin", "Jardiance"], "tablet", "10 mg")
add("Dapagliflozina", ["Dapagliflozin", "Forxiga", "Farxiga"], "tablet", "10 mg")
add("Liraglutida", ["Liraglutide", "Victoza", "Saxenda"], "injection", "")
add("Semaglutida", ["Semaglutide", "Ozempic", "Wegovy", "Rybelsus"], "injection / tablet", "")
add("Insulina glargina", ["Insulin glargine", "Lantus", "Basaglar", "Toujeo"], "injection", "")
add("Insulina NPH", ["NPH insulin", "Humulin N", "Novolin N"], "injection", "")
add("Insulina regular", ["Regular insulin", "Humulin R"], "injection", "")
add("Insulina aspart", ["Insulin aspart", "NovoRapid", "NovoLog"], "injection", "")
add("Insulina lispro", ["Insulin lispro", "Humalog"], "injection", "")
add("Levotiroxina", ["Levothyroxine", "Puran T4", "Euthyrox", "Synthroid", "Levoid"], "tablet", "50 mcg")
add("Metimazol", ["Methimazole", "Tapazol"], "tablet", "10 mg")

add("Salbutamol", ["Albuterol", "Aerolin", "Ventolin", "Proventil"], "inhaler", "100 mcg")
add("Albuterol", ["Salbutamol", "Ventolin"], "inhaler", "")
add("Formoterol", ["Foradil", "Oxis"], "inhaler", "")
add("Salmeterol", ["Serevent"], "inhaler", "")
add("Ipratrópio", ["Ipratropium", "Atrovent"], "inhaler", "")
add("Tiotrópio", ["Tiotropium", "Spiriva"], "inhaler", "")
add("Montelucaste", ["Montelukast", "Singulair"], "tablet", "10 mg")
add("Teofilina", ["Theophylline"], "tablet", "")
add("Acebrofilina", ["Acebrophylline", "Bronfilin", "Filinar"], "syrup", "")
add("Ambroxol", ["Mucosolvan", "Ambrol"], "syrup", "")
add("Acetilcisteína", ["Acetylcysteine", "Fluimucil", "ACC"], "sachet", "600 mg")
add("Bromexina", ["Bromhexine", "Bisolvon"], "syrup", "")
add("Dextrometorfano", ["Dextromethorphan", "Benalet"], "syrup", "")
add("Soro fisiológico nasal", ["Soro nasal", "Saline nasal", "Nasal saline", "Sorine"], "spray / drops", "0.9%")
add("Oximetazolina", ["Oxymetazoline", "Afrin", "Nasivin"], "nasal spray", "")
add("Loratadina", ["Loratadine", "Claritin", "Loratamed"], "tablet", "10 mg")
add("Desloratadina", ["Desloratadine", "Desalex", "Clarinex"], "tablet", "5 mg")
add("Cetirizina", ["Cetirizine", "Zyrtec", "Cetyrin"], "tablet", "10 mg")
add("Levocetirizina", ["Levocetirizine", "Xyzal"], "tablet", "5 mg")
add("Fexofenadina", ["Fexofenadine", "Allegra"], "tablet", "180 mg")
add("Difenidramina", ["Diphenhydramine", "Benadryl"], "tablet", "25 mg")
add("Hidroxizina", ["Hydroxyzine", "Atarax"], "tablet", "25 mg")
add("Prometazina", ["Promethazine", "Fenergan"], "tablet", "25 mg")
add("Clorfeniramina", ["Chlorpheniramine", "Polaramine"], "tablet", "4 mg")

add("Sertralina", ["Sertraline", "Zoloft", "Assert"], "tablet", "50 mg")
add("Fluoxetina", ["Fluoxetine", "Prozac", "Daforin"], "capsule", "20 mg")
add("Escitalopram", ["Lexapro", "Espran"], "tablet", "10 mg")
add("Citalopram", ["Celexa", "Cipramil"], "tablet", "20 mg")
add("Paroxetina", ["Paroxetine", "Paxil", "Pondera"], "tablet", "20 mg")
add("Venlafaxina", ["Venlafaxine", "Effexor", "Alenthus"], "capsule", "75 mg")
add("Duloxetina", ["Duloxetine", "Cymbalta"], "capsule", "30 mg")
add("Amitriptilina", ["Amitriptyline", "Tryptanol"], "tablet", "25 mg")
add("Nortriptilina", ["Nortriptyline", "Pamelor"], "capsule", "25 mg")
add("Bupropiona", ["Bupropion", "Wellbutrin", "Zyban"], "tablet", "150 mg")
add("Mirtazapina", ["Mirtazapine", "Remeron"], "tablet", "30 mg")
add("Trazodona", ["Trazodone", "Donaren"], "tablet", "50 mg")
add("Clonazepam", ["Rivotril", "Klonopin"], "tablet", "0.5 mg")
add("Diazepam", ["Valium", "Compaz"], "tablet", "10 mg")
add("Alprazolam", ["Xanax", "Frontal"], "tablet", "0.5 mg")
add("Lorazepam", ["Ativan", "Lorax"], "tablet", "1 mg")
add("Bromazepam", ["Lexotan"], "tablet", "3 mg")
add("Zolpidem", ["Ambien", "Stilnox"], "tablet", "10 mg")
add("Zopiclona", ["Zopiclone", "Imovane"], "tablet", "7.5 mg")
add("Lítio", ["Lithium", "Carbolitium"], "tablet", "300 mg")
add("Valproato de sódio", ["Valproate", "Depakene", "Depakote"], "tablet", "500 mg")
add("Carbamazepina", ["Carbamazepine", "Tegretol"], "tablet", "200 mg")
add("Lamotrigina", ["Lamotrigine", "Lamictal"], "tablet", "100 mg")
add("Levetiracetam", ["Keppra"], "tablet", "500 mg")
add("Topiramato", ["Topiramate", "Topamax"], "tablet", "50 mg")
add("Fenitoína", ["Phenytoin", "Hidantal"], "tablet", "100 mg")
add("Fenobarbital", ["Phenobarbital", "Gardenal"], "tablet", "100 mg")
add("Gabapentina", ["Gabapentin", "Neurontin"], "capsule", "300 mg")
add("Pregabalina", ["Pregabalin", "Lyrica"], "capsule", "75 mg")
add("Risperidona", ["Risperidone", "Risperdal"], "tablet", "2 mg")
add("Quetiapina", ["Quetiapine", "Seroquel"], "tablet", "25 mg")
add("Olanzapina", ["Olanzapine", "Zyprexa"], "tablet", "5 mg")
add("Aripiprazol", ["Aripiprazole", "Abilify"], "tablet", "10 mg")
add("Haloperidol", ["Haldol"], "tablet", "5 mg")
add("Metilfenidato", ["Methylphenidate", "Ritalina", "Ritalin", "Concerta"], "tablet", "10 mg")
add("Lisdexanfetamina", ["Lisdexamfetamine", "Venvanse", "Vyvanse"], "capsule", "30 mg")
add("Donepezila", ["Donepezil", "Aricept"], "tablet", "5 mg")
add("Memantina", ["Memantine", "Ebixa", "Namenda"], "tablet", "10 mg")

add("Sildenafila", ["Sildenafil", "Viagra", "Revatio"], "tablet", "50 mg")
add("Tadalafila", ["Tadalafil", "Cialis"], "tablet", "5 mg")
add("Tansulosina", ["Tamsulosin", "Flomax", "Secotex"], "capsule", "0.4 mg")
add("Finasterida", ["Finasteride", "Propecia", "Proscar"], "tablet", "1 mg")
add("Dutasterida", ["Dutasteride", "Avodart"], "capsule", "0.5 mg")
add("Ocitocina", ["Oxytocin"], "injection", "")
add("Misoprostol", ["Cytotec"], "tablet", "")
add("Levonorgestrel", ["Plan B", "Postinor", "DIU LNG"], "tablet", "1.5 mg")
add("Etinilestradiol + Levonorgestrel", ["Combined oral contraceptive", "Microvlar", "Selene"], "tablet", "")
add("Desogestrel", ["Cerazette", "Nactali"], "tablet", "")
add("Medroxiprogesterona", ["Medroxyprogesterone", "Depo-Provera"], "injection", "")
add("Estradiol", ["Estradot", "Climene"], "patch / gel", "")
add("Progesterona", ["Progesterone", "Utrogestan"], "capsule", "100 mg")
add("Tadalafil", ["Tadalafila", "Cialis"], "tablet", "20 mg")

add("Varfarina", ["Warfarin", "Marevan", "Coumadin"], "tablet", "5 mg")
add("Rivaroxabana", ["Rivaroxaban", "Xarelto"], "tablet", "20 mg")
add("Apixabana", ["Apixaban", "Eliquis"], "tablet", "5 mg")
add("Dabigatrana", ["Dabigatran", "Pradaxa"], "capsule", "150 mg")
add("Enoxaparina", ["Enoxaparin", "Clexane", "Lovenox"], "injection", "")
add("Heparina", ["Heparin"], "injection", "")
add("Clopidogrel", ["Plavix", "Iscover"], "tablet", "75 mg")
add("Ticagrelor", ["Brilinta", "Brilique"], "tablet", "90 mg")
add("AAS infantil", ["Baby aspirin", "Aspirina Prevent"], "tablet", "100 mg")
add("Digoxina", ["Digoxin", "Lanoxin"], "tablet", "0.25 mg")
add("Amiodarona", ["Amiodarone", "Ancoron", "Cordarone"], "tablet", "200 mg")
add("Isossorbida", ["Isosorbide", "Isordil", "Monocordil"], "tablet", "10 mg")
add("Dinitrato de isossorbida", ["Isosorbide dinitrate"], "tablet", "10 mg")
add("Trinitrato de glicerila", ["Nitroglycerin", "Nitradisc"], "sublingual", "")

add("Alopurinol", ["Allopurinol", "Zyloric"], "tablet", "100 mg")
add("Colchicina", ["Colchicine", "Colchis"], "tablet", "0.5 mg")
add("Alendronato", ["Alendronate", "Fosamax"], "tablet", "70 mg")
add("Risedronato", ["Risedronate", "Actonel"], "tablet", "35 mg")
add("Carbonato de cálcio", ["Calcium carbonate", "Oscal"], "tablet", "500 mg")
add("Vitamina D", ["Cholecalciferol", "Colecalciferol", "Addera D3", "DePura"], "drops / capsule", "")
add("Ácido fólico", ["Folic acid", "Folacin", "Endofolin"], "tablet", "5 mg")
add("Sulfato ferroso", ["Ferrous sulfate", "Noripurum", "Hematofer"], "tablet / drops", "")
add("Complexo B", ["Vitamin B complex", "Citoneurin", "Neurobion"], "tablet", "")
add("Vitamina C", ["Ascorbic acid", "Redoxon", "Cebion"], "tablet", "500 mg")
add("Vitamina B12", ["Cyanocobalamin", "Bedoz"], "injection / tablet", "")
add("Tiamina", ["Thiamine", "Vitamin B1"], "tablet", "300 mg")
add("Piridoxina", ["Pyridoxine", "Vitamin B6"], "tablet", "")
add("Magnésio", ["Magnesium", "Magnesio quelado"], "tablet", "")
add("Zinco", ["Zinc", "Zinco quelado"], "tablet", "")
add("Ômega-3", ["Omega-3", "Fish oil"], "capsule", "")

add("Sildenafil", ["Sildenafila", "Viagra"], "tablet", "50 mg")
add("Ciclosporina", ["Cyclosporine", "Sandimmun"], "capsule", "")
add("Metotrexato", ["Methotrexate", "Rheumatrex"], "tablet", "2.5 mg")
add("Hidroxicloroquina", ["Hydroxychloroquine", "Plaquenil", "Reuquinol"], "tablet", "400 mg")
add("Azatioprina", ["Azathioprine", "Imuran"], "tablet", "50 mg")
add("Micofenolato", ["Mycophenolate", "CellCept"], "tablet", "500 mg")
add("Adalimumabe", ["Adalimumab", "Humira"], "injection", "")
add("Etanercepte", ["Etanercept", "Enbrel"], "injection", "")
add("Infliximabe", ["Infliximab", "Remicade"], "infusion", "")

add("Timolol", ["Timoptol", "Timoptic"], "eye drops", "0.5%")
add("Latanoprosta", ["Latanoprost", "Xalatan"], "eye drops", "")
add("Dorzolamida", ["Dorzolamide", "Trusopt"], "eye drops", "")
add("Brimonidina", ["Brimonidine", "Alphagan"], "eye drops", "")
add("Tropicamida", ["Mydriacyl"], "eye drops", "")
add("Tobramicina", ["Tobrex"], "eye drops", "")
add("Ciprofloxacino oftálmico", ["Ciloxan"], "eye drops", "")
add("Lubrificante ocular", ["Artificial tears", "Lacrima", "Refresh"], "eye drops", "")
add("Miconazol", ["Miconazole", "Daktarin"], "cream", "")
add("Cetoconazol", ["Ketoconazole", "Nizoral"], "cream / shampoo", "")
add("Terbinafina", ["Terbinafine", "Lamisil"], "cream / tablet", "250 mg")
add("Clotrimazol", ["Clotrimazole", "Canesten", "Gino-Canesten"], "cream", "")
add("Permetrina", ["Permethrin", "Pazol"], "cream / lotion", "")
add("Benzil benzoato", ["Benzyl benzoate", "Acarsan"], "lotion", "")
add("Permanganato de potássio", ["Potassium permanganate"], "solution", "")
add("Nistatina creme", ["Nystatin cream"], "cream", "")
add("Neomicina + Bacitracina", ["Neosporin", "Nebacetin"], "ointment", "")
add("Sulfadiazina de prata", ["Silver sulfadiazine", "Dermazine"], "cream", "")
add("Lidocaína", ["Lidocaine", "Xylocaine"], "gel / injection", "")
add("Benzocaína", ["Benzocaine"], "gel", "")

add("Sinvastatina", [], "tablet", "40 mg")  # duplicate name ignored later
add("Clonidina", ["Clonidine", "Atensina"], "tablet", "0.150 mg")
add("Doxazosina", ["Doxazosin", "Cardura"], "tablet", "2 mg")
add("Prazosina", ["Prazosin", "Minipress"], "tablet", "1 mg")
add("Hidralazina", ["Hydralazine", "Apresoline"], "tablet", "25 mg")
add("Nitroprussiato", ["Nitroprusside"], "injection", "")
add("Noradrenalina", ["Norepinephrine", "Levophed"], "injection", "")
add("Adrenalina", ["Epinephrine", "Adrenalin", "EpiPen"], "injection", "")
add("Dopamina", ["Dopamine"], "injection", "")
add("Dobutamina", ["Dobutamine"], "injection", "")
add("Atropina", ["Atropine"], "injection / drops", "")
add("Flumazenil", ["Anexate"], "injection", "")
add("Naloxona", ["Naloxone", "Narcan"], "injection", "")
add("Glicose 50%", ["Dextrose 50%", "Glucose"], "injection", "")
add("Soro fisiológico", ["Normal saline", "NaCl 0.9%", "SF 0.9%"], "IV / nasal", "0.9%")
add("Ringer lactato", ["Lactated Ringer", "RL"], "IV", "")
add("Soro glicosado", ["Dextrose saline", "SG 5%"], "IV", "5%")
add("Dipirona injetável", ["Metamizole injection", "Novalgina amp"], "injection", "1 g")
add("Ondansetrona injetável", ["Zofran injection"], "injection", "8 mg")
add("Hidrocortisona injetável", ["Solu-Cortef"], "injection", "")
add("Metilprednisolona", ["Methylprednisolone", "Solu-Medrol"], "injection / tablet", "")

add("Tadalafila 5 mg", ["Cialis daily"], "tablet", "5 mg")
add("Sildenafila 25 mg", ["Viagra 25"], "tablet", "25 mg")

add("Polivitamínico", ["Multivitamin", "Centrum", "Farmácia de manipulação poly"], "tablet", "")
add("Probiótico", ["Probiotic", "Floratil", "Saccharomyces boulardii"], "capsule", "")
add("Saccharomyces boulardii", ["Floratil"], "capsule", "")
add("Lactobacillus", ["Lactobacillus rhamnosus", "LGG"], "capsule", "")

add("Hidróxido de alumínio", ["Aluminum hydroxide", "Pepsamar"], "suspension", "")
add("Bicarbonato de sódio", ["Sodium bicarbonate"], "tablet", "")
add("Carvão ativado", ["Activated charcoal"], "powder", "")
add("Óleo mineral", ["Mineral oil", "Nujol"], "liquid", "")
add("Glicerina", ["Glycerin suppository"], "suppository", "")
add("Bisacodil", ["Bisacodyl", "Dulcolax", "Laxan"], "tablet", "5 mg")
add("Picosulfato de sódio", ["Sodium picosulfate", "Guttalax"], "drops", "")

add("Cinarizina", ["Cinnarizine", "Stugeron"], "tablet", "25 mg")
add("Flunarizina", ["Flunarizine", "Sibelium"], "tablet", "10 mg")
add("Betahistina", ["Betahistine", "Serc", "Labs"], "tablet", "16 mg")
add("Meclizina", ["Meclizine", "Meclin", "Antivert"], "tablet", "25 mg")
add("Sumatriptana", ["Sumatriptan", "Imigran", "Imitrex"], "tablet", "50 mg")
add("Rizatriptana", ["Rizatriptan", "Maxalt"], "tablet", "10 mg")
add("Ergotamina", ["Ergotamine", "Cefalium"], "tablet", "")
add("Dipirona + Orfenadrina + Cafeína", ["Dorflex", "Torsilax"], "tablet", "")
add("Paracetamol + Cafeína", ["Tylenol DC", "Excedrin"], "tablet", "")
add("Paracetamol + Codeína", ["Tylex", "Tylenol with codeine"], "tablet", "")
add("Paracetamol + Tramadol", ["Ultracet", "Revange"], "tablet", "")

add("Oseltamivir", [], "capsule", "30 mg")
add("Molnupiravir", ["Lagevrio"], "capsule", "")
add("Nirmatrelvir + Ritonavir", ["Paxlovid"], "tablet", "")
add("Remdesivir", ["Veklury"], "infusion", "")

add("Rifampicina", ["Rifampin", "Rifadin"], "capsule", "300 mg")
add("Isoniazida", ["Isoniazid", "INH"], "tablet", "300 mg")
add("Pirazinamida", ["Pyrazinamide"], "tablet", "500 mg")
add("Etambutol", ["Ethambutol"], "tablet", "400 mg")
add("Estreptomicina", ["Streptomycin"], "injection", "")

add("Arteméter + Lumefantrina", ["Coartem", "Riamet"], "tablet", "")
add("Primaquina", ["Primaquine"], "tablet", "")
add("Cloroquina", ["Chloroquine"], "tablet", "")
add("Doxiciclina malária", ["Doxycycline malaria"], "capsule", "100 mg")

add("Benznidazol", ["Rochagan"], "tablet", "")
add("Nifurtimox", ["Lampit"], "tablet", "")

add("Praziquantel", ["Biltricide", "Cestox"], "tablet", "")
add("Tiabendazol", ["Thiabendazole"], "tablet", "")

add("Zidovudina", ["Zidovudine", "AZT", "Retrovir"], "tablet", "")
add("Lamivudina", ["Lamivudine", "3TC", "Epivir"], "tablet", "")
add("Tenofovir", ["TDF", "TDF/FTC", "Viread", "Truvada"], "tablet", "")
add("Efavirenz", ["Sustiva", "Stocrin"], "tablet", "600 mg")
add("Dolutegravir", ["Tivicay", "DTG"], "tablet", "50 mg")
add("Ritonavir", ["Norvir"], "tablet", "")
add("Lopinavir + Ritonavir", ["Kaletra"], "tablet", "")

add("Sofosbuvir", ["Sovaldi"], "tablet", "")
add("Daclatasvir", ["Daklinza"], "tablet", "")
add("Entecavir", ["Baraclude"], "tablet", "0.5 mg")
add("Tenofovir alafenamida", ["TAF", "Vemlidy"], "tablet", "")

add("Filgrastim", ["Neupogen"], "injection", "")
add("Eritropoetina", ["Epoetin", "Eprex"], "injection", "")
add("Ferro intravenoso", ["Iron sucrose", "Venofer", "Noripurum IV"], "injection", "")

add("Ciclofosfamida", ["Cyclophosphamide", "Cytoxan"], "tablet / infusion", "")
add("Paclitaxel", ["Taxol"], "infusion", "")
add("Carboplatina", ["Carboplatin"], "infusion", "")
add("Cisplatina", ["Cisplatin"], "infusion", "")
add("Tamoxifeno", ["Tamoxifen", "Nolvadex"], "tablet", "20 mg")
add("Anastrozol", ["Arimidex"], "tablet", "1 mg")
add("Letrozol", ["Letrozole", "Femara"], "tablet", "2.5 mg")
add("Goserrelina", ["Goserelin", "Zoladex"], "implant", "")
add("Bicalutamida", ["Casodex"], "tablet", "50 mg")

add("Insulina degludeca", ["Insulin degludec", "Tresiba"], "injection", "")
add("Insulina detemir", ["Insulin detemir", "Levemir"], "injection", "")
add("Pioglitazona", ["Pioglitazone", "Actos"], "tablet", "15 mg")
add("Acarbose", ["Glucobay"], "tablet", "50 mg")
add("Repaglinida", ["Repaglinide", "Prandin"], "tablet", "1 mg")
add("Canagliflozina", ["Canagliflozin", "Invokana"], "tablet", "100 mg")
add("Linagliptina", ["Linagliptin", "Trajenta"], "tablet", "5 mg")
add("Saxagliptina", ["Saxagliptin", "Onglyza"], "tablet", "5 mg")

add("Ticagrelor", [], "tablet", "60 mg")
add("Prasugrel", ["Efient", "Effient"], "tablet", "10 mg")
add("Cilostazol", ["Pletal", "Vasogard"], "tablet", "100 mg")
add("Pentoxifilina", ["Pentoxifylline", "Trental"], "tablet", "400 mg")
add("Diosmina", ["Diosmin", "Daflon", "Venalot"], "tablet", "")
add("Rutosídeo", ["Rutin", "Venoruton"], "tablet", "")

add("Pantoprazole", ["Pantoprazol"], "tablet", "40 mg")
add("Ranitidine", ["Ranitidina"], "tablet", "150 mg")
add("Sucralfato", ["Sucralfate", "Sucrafil"], "suspension", "")
add("Bismuto", ["Bismuth", "Pepto-Bismol"], "tablet", "")
add("Claritromicina", ["Clarithromycin", "Klaricid", "Biaxin"], "tablet", "500 mg")
add("Amoxicilina H. pylori", ["Amoxil HP"], "capsule", "500 mg")

add("Fenoterol", ["Berotec"], "inhaler", "")
add("Fenoterol + Ipratrópio", ["Berodual"], "inhaler", "")
add("Budesonida + Formoterol", ["Symbicort", "Alenia", "Vannair"], "inhaler", "")
add("Fluticasona + Salmeterol", ["Seretide", "Advair"], "inhaler", "")
add("Beclometasona + Formoterol", ["Foster", "Fostair"], "inhaler", "")
add("Prednisolona xarope", ["Prelone syrup"], "syrup", "")
add("Dexametasona elixir", ["Decadron elixir"], "elixir", "")

add("Desogestrel 75 mcg", ["Cerazette"], "tablet", "75 mcg")
add("Drospirenona + Etinilestradiol", ["Yasmin", "Elani", "Iumi"], "tablet", "")
add("Ciproterona + Etinilestradiol", ["Diane 35", "Selene"], "tablet", "")
add("Noretisterona", ["Norethisterone", "Primolut-Nor"], "tablet", "10 mg")
add("Cabergolina", ["Cabergoline", "Dostinex"], "tablet", "0.5 mg")
add("Bromocriptina", ["Bromocriptine", "Parlodel"], "tablet", "2.5 mg")

add("Sinvastatina 10 mg", ["Zocor 10"], "tablet", "10 mg")
add("Atorvastatina 10 mg", ["Lipitor 10"], "tablet", "10 mg")
add("Atorvastatina 40 mg", ["Lipitor 40"], "tablet", "40 mg")
add("Rosuvastatina 5 mg", ["Crestor 5"], "tablet", "5 mg")
add("Rosuvastatina 20 mg", ["Crestor 20"], "tablet", "20 mg")
add("Losartana 25 mg", ["Cozaar 25"], "tablet", "25 mg")
add("Losartana 100 mg", ["Cozaar 100"], "tablet", "100 mg")
add("Enalapril 5 mg", ["Renitec 5"], "tablet", "5 mg")
add("Enalapril 20 mg", ["Renitec 20"], "tablet", "20 mg")
add("Anlodipino 2.5 mg", ["Norvasc 2.5"], "tablet", "2.5 mg")
add("Anlodipino 10 mg", ["Norvasc 10"], "tablet", "10 mg")
add("Metformina 500 mg", ["Glifage 500"], "tablet", "500 mg")
add("Metformina XR", ["Glifage XR", "Glucophage XR"], "tablet", "500 mg")
add("Omeprazol 40 mg", ["Losec 40"], "capsule", "40 mg")
add("Pantoprazol 20 mg", ["Pantozol 20"], "tablet", "20 mg")
add("Ibuprofeno 200 mg", ["Advil 200"], "tablet", "200 mg")
add("Ibuprofeno 600 mg", ["Alivium 600"], "tablet", "600 mg")
add("Paracetamol 500 mg", ["Tylenol 500"], "tablet", "500 mg")
add("Paracetamol 750 mg", ["Tylenol 750", "Dôrico 750"], "tablet", "750 mg")
add("Dipirona 1 g", ["Novalgina 1 g"], "tablet", "1 g")
add("Dipirona gotas", ["Novalgina gotas", "Anador gotas"], "drops", "500 mg/ml")
add("Amoxicilina 250 mg/5 ml", ["Amoxil xarope"], "syrup", "250 mg/5 ml")
add("Amoxicilina 400 mg/5 ml", ["Amoxil BD"], "syrup", "400 mg/5 ml")
add("Ibuprofeno 100 mg/5 ml", ["Alivium suspensão", "Advil children"], "suspension", "100 mg/5 ml")
add("Paracetamol 200 mg/ml", ["Tylenol gotas"], "drops", "200 mg/ml")
add("Prednisolona 3 mg/ml", ["Prelone"], "syrup", "3 mg/ml")
add("Azitromicina 200 mg/5 ml", ["Zitromax suspensão"], "suspension", "200 mg/5 ml")
add("Nimesulida gotas", ["Nisulid gotas"], "drops", "")
add("Acebrofilina xarope", ["Filinar xarope"], "syrup", "")
add("Ambroxol xarope", ["Mucosolvan xarope"], "syrup", "")
add("Loratadina xarope", ["Claritin xarope"], "syrup", "5 mg/5 ml")
add("Desloratadina xarope", ["Desalex xarope"], "syrup", "")
add("Salbutamol xarope", ["Aerolin xarope"], "syrup", "")
add("Sulfato ferroso gotas", ["Noripurum gotas"], "drops", "")
add("Vitamina D gotas", ["Addera D3 gotas"], "drops", "")
add("Simeticona gotas", ["Luftal gotas"], "drops", "")
add("Domperidona suspensão", ["Motilium suspensão"], "suspension", "")
add("Nistatina suspensão", ["Micostatin"], "oral suspension", "")

# English INN extras (global essentials)
ENGLISH = [
    ("Warfarin", ["Varfarina"], "tablet", "5 mg"),
    ("Hydrochlorothiazide", ["Hidroclorotiazida"], "tablet", "25 mg"),
    ("Furosemide", ["Furosemida", "Lasix"], "tablet", "40 mg"),
    ("Spironolactone", ["Espironolactona"], "tablet", "25 mg"),
    ("Amlodipine", ["Anlodipino"], "tablet", "5 mg"),
    ("Lisinopril", ["Zestril"], "tablet", "10 mg"),
    ("Ramipril", ["Altace"], "tablet", "5 mg"),
    ("Candesartan", ["Candesartana"], "tablet", "8 mg"),
    ("Olmesartan", ["Olmesartana"], "tablet", "20 mg"),
    ("Valsartan", ["Valsartana"], "tablet", "80 mg"),
    ("Metoprolol tartrate", ["Lopressor"], "tablet", "50 mg"),
    ("Metoprolol succinate", ["Toprol XL", "Selozok"], "tablet", "50 mg"),
    ("Carvedilol", ["Coreg"], "tablet", "6.25 mg"),
    ("Bisoprolol", ["Zebeta"], "tablet", "5 mg"),
    ("Simvastatin", ["Sinvastatina"], "tablet", "20 mg"),
    ("Atorvastatin", ["Atorvastatina"], "tablet", "20 mg"),
    ("Rosuvastatin", ["Rosuvastatina"], "tablet", "10 mg"),
    ("Ezetimibe", ["Ezetimiba"], "tablet", "10 mg"),
    ("Clopidogrel", ["Plavix"], "tablet", "75 mg"),
    ("Apixaban", ["Eliquis"], "tablet", "5 mg"),
    ("Rivaroxaban", ["Xarelto"], "tablet", "20 mg"),
    ("Dabigatran", ["Pradaxa"], "capsule", "150 mg"),
    ("Levothyroxine", ["Levotiroxina", "Synthroid"], "tablet", "50 mcg"),
    ("Metformin XR", ["Glucophage XR"], "tablet", "500 mg"),
    ("Glipizide", ["Glucotrol"], "tablet", "5 mg"),
    ("Glyburide", ["Glibenclamida", "Micronase"], "tablet", "5 mg"),
    ("Sitagliptin", ["Januvia"], "tablet", "100 mg"),
    ("Empagliflozin", ["Jardiance"], "tablet", "10 mg"),
    ("Dapagliflozin", ["Farxiga"], "tablet", "10 mg"),
    ("Insulin glargine", ["Lantus"], "injection", ""),
    ("Insulin lispro", ["Humalog"], "injection", ""),
    ("Omeprazole", ["Omeprazol"], "capsule", "20 mg"),
    ("Pantoprazole", ["Protonix"], "tablet", "40 mg"),
    ("Famotidine", ["Pepcid"], "tablet", "20 mg"),
    ("Ondansetron", ["Zofran"], "tablet", "4 mg"),
    ("Loperamide", ["Imodium"], "tablet", "2 mg"),
    ("Docusate", ["Colace"], "capsule", "100 mg"),
    ("Polyethylene glycol 3350", ["MiraLAX", "Macrogol"], "powder", ""),
    ("Senna", ["Sennosides", "Senokot"], "tablet", ""),
    ("Ibuprofen", ["Advil"], "tablet", "200 mg"),
    ("Naproxen", ["Aleve"], "tablet", "220 mg"),
    ("Acetaminophen extra strength", ["Tylenol Extra Strength"], "tablet", "500 mg"),
    ("Aspirin 81 mg", ["Baby aspirin"], "tablet", "81 mg"),
    ("Celecoxib", ["Celebrex"], "capsule", "200 mg"),
    ("Meloxicam", ["Mobic"], "tablet", "15 mg"),
    ("Cyclobenzaprine", ["Flexeril"], "tablet", "10 mg"),
    ("Baclofen", ["Lioresal"], "tablet", "10 mg"),
    ("Tizanidine", ["Zanaflex"], "tablet", "2 mg"),
    ("Tramadol", ["Ultram"], "tablet", "50 mg"),
    ("Hydrocodone-acetaminophen", ["Norco", "Vicodin"], "tablet", ""),
    ("Oxycodone", ["OxyContin", "Roxicodone"], "tablet", "5 mg"),
    ("Morphine sulfate", ["MS Contin"], "tablet", ""),
    ("Gabapentin", ["Neurontin"], "capsule", "300 mg"),
    ("Pregabalin", ["Lyrica"], "capsule", "75 mg"),
    ("Duloxetine", ["Cymbalta"], "capsule", "30 mg"),
    ("Sertraline", ["Zoloft"], "tablet", "50 mg"),
    ("Escitalopram", ["Lexapro"], "tablet", "10 mg"),
    ("Fluoxetine", ["Prozac"], "capsule", "20 mg"),
    ("Bupropion XL", ["Wellbutrin XL"], "tablet", "150 mg"),
    ("Trazodone", ["Desyrel"], "tablet", "50 mg"),
    ("Mirtazapine", ["Remeron"], "tablet", "15 mg"),
    ("Alprazolam", ["Xanax"], "tablet", "0.25 mg"),
    ("Lorazepam", ["Ativan"], "tablet", "1 mg"),
    ("Diazepam", ["Valium"], "tablet", "5 mg"),
    ("Clonazepam", ["Klonopin"], "tablet", "0.5 mg"),
    ("Zolpidem", ["Ambien"], "tablet", "5 mg"),
    ("Quetiapine", ["Seroquel"], "tablet", "25 mg"),
    ("Aripiprazole", ["Abilify"], "tablet", "5 mg"),
    ("Risperidone", ["Risperdal"], "tablet", "1 mg"),
    ("Olanzapine", ["Zyprexa"], "tablet", "5 mg"),
    ("Lithium carbonate", ["Lithobid"], "tablet", "300 mg"),
    ("Lamotrigine", ["Lamictal"], "tablet", "25 mg"),
    ("Valproic acid", ["Depakote"], "tablet", "250 mg"),
    ("Levetiracetam", ["Keppra"], "tablet", "500 mg"),
    ("Topiramate", ["Topamax"], "tablet", "25 mg"),
    ("Carbamazepine", ["Tegretol"], "tablet", "200 mg"),
    ("Phenytoin", ["Dilantin"], "capsule", "100 mg"),
    ("Donepezil", ["Aricept"], "tablet", "5 mg"),
    ("Memantine", ["Namenda"], "tablet", "10 mg"),
    ("Methylphenidate", ["Ritalin", "Concerta"], "tablet", "10 mg"),
    ("Amphetamine salts", ["Adderall"], "tablet", "10 mg"),
    ("Lisdexamfetamine", ["Vyvanse"], "capsule", "30 mg"),
    ("Sumatriptan", ["Imitrex"], "tablet", "50 mg"),
    ("Propranolol", ["Inderal"], "tablet", "10 mg"),
    ("Amoxicillin", ["Amoxil"], "capsule", "500 mg"),
    ("Amoxicillin-clavulanate", ["Augmentin"], "tablet", "875/125 mg"),
    ("Azithromycin", ["Zithromax", "Z-Pak"], "tablet", "250 mg"),
    ("Doxycycline", ["Vibramycin"], "capsule", "100 mg"),
    ("Cephalexin", ["Keflex"], "capsule", "500 mg"),
    ("Ciprofloxacin", ["Cipro"], "tablet", "500 mg"),
    ("Levofloxacin", ["Levaquin"], "tablet", "500 mg"),
    ("Metronidazole", ["Flagyl"], "tablet", "500 mg"),
    ("Nitrofurantoin", ["Macrobid"], "capsule", "100 mg"),
    ("Trimethoprim-sulfamethoxazole", ["Bactrim", "Septra"], "tablet", ""),
    ("Fluconazole", ["Diflucan"], "tablet", "150 mg"),
    ("Acyclovir", ["Zovirax"], "tablet", "400 mg"),
    ("Valacyclovir", ["Valtrex"], "tablet", "500 mg"),
    ("Oseltamivir", ["Tamiflu"], "capsule", "75 mg"),
    ("Prednisone", ["Deltasone"], "tablet", "20 mg"),
    ("Methylprednisolone dose pack", ["Medrol Dosepak"], "tablet", ""),
    ("Hydrocortisone cream", ["Cortizone"], "cream", "1%"),
    ("Triamcinolone cream", ["Kenalog"], "cream", ""),
    ("Albuterol inhaler", ["Ventolin", "ProAir"], "inhaler", ""),
    ("Budesonide-formoterol", ["Symbicort"], "inhaler", ""),
    ("Fluticasone-salmeterol", ["Advair"], "inhaler", ""),
    ("Tiotropium", ["Spiriva"], "inhaler", ""),
    ("Montelukast", ["Singulair"], "tablet", "10 mg"),
    ("Cetirizine", ["Zyrtec"], "tablet", "10 mg"),
    ("Loratadine", ["Claritin"], "tablet", "10 mg"),
    ("Fexofenadine", ["Allegra"], "tablet", "180 mg"),
    ("Diphenhydramine", ["Benadryl"], "capsule", "25 mg"),
    ("Fluticasone nasal", ["Flonase"], "nasal spray", ""),
    ("Mometasone nasal", ["Nasonex"], "nasal spray", ""),
    ("Pseudoephedrine", ["Sudafed"], "tablet", "60 mg"),
    ("Phenylephrine", ["Sudafed PE"], "tablet", "10 mg"),
    ("Guaifenesin", ["Mucinex"], "tablet", "600 mg"),
    ("Dextromethorphan", ["Delsym"], "syrup", ""),
    ("Saline nasal spray", ["Simply Saline", "Soro nasal"], "spray", ""),
    ("Tamsulosin", ["Flomax"], "capsule", "0.4 mg"),
    ("Finasteride", ["Proscar", "Propecia"], "tablet", "5 mg"),
    ("Sildenafil", ["Viagra"], "tablet", "50 mg"),
    ("Tadalafil", ["Cialis"], "tablet", "5 mg"),
    ("Oxybutynin", ["Ditropan"], "tablet", "5 mg"),
    ("Mirabegron", ["Myrbetriq"], "tablet", "25 mg"),
    ("Allopurinol", ["Zyloprim"], "tablet", "100 mg"),
    ("Colchicine", ["Colcrys"], "tablet", "0.6 mg"),
    ("Alendronate", ["Fosamax"], "tablet", "70 mg"),
    ("Cholecalciferol", ["Vitamin D3"], "capsule", "1000 IU"),
    ("Calcium carbonate", ["Tums", "Oscal"], "tablet", ""),
    ("Ferrous sulfate", ["Feosol"], "tablet", "325 mg"),
    ("Folic acid", ["Folate"], "tablet", "1 mg"),
    ("Cyanocobalamin", ["Vitamin B12"], "tablet", "1000 mcg"),
    ("Potassium chloride", ["Klor-Con"], "tablet", "20 mEq"),
    ("Magnesium oxide", ["Mag-Ox"], "tablet", "400 mg"),
    ("Atorvastatin 40 mg", ["Lipitor 40"], "tablet", "40 mg"),
    ("Rosuvastatin 40 mg", ["Crestor 40"], "tablet", "40 mg"),
    ("Losartan 50 mg", ["Cozaar 50"], "tablet", "50 mg"),
    ("Losartan 100 mg", ["Cozaar 100"], "tablet", "100 mg"),
    ("Amlodipine 10 mg", ["Norvasc 10"], "tablet", "10 mg"),
    ("Lisinopril 20 mg", ["Zestril 20"], "tablet", "20 mg"),
    ("Lisinopril 40 mg", ["Zestril 40"], "tablet", "40 mg"),
    ("Metformin 1000 mg", ["Glucophage 1000"], "tablet", "1000 mg"),
    ("Omeprazole 40 mg", ["Prilosec 40"], "capsule", "40 mg"),
    ("Pantoprazole 40 mg", ["Protonix 40"], "tablet", "40 mg"),
    ("Atorvastatin 80 mg", ["Lipitor 80"], "tablet", "80 mg"),
    ("Carvedilol 25 mg", ["Coreg 25"], "tablet", "25 mg"),
    ("Furosemide 20 mg", ["Lasix 20"], "tablet", "20 mg"),
    ("Furosemide 80 mg", ["Lasix 80"], "tablet", "80 mg"),
    ("Hydrochlorothiazide 12.5 mg", ["HCTZ 12.5"], "tablet", "12.5 mg"),
    ("Spironolactone 50 mg", ["Aldactone 50"], "tablet", "50 mg"),
    ("Clopidogrel 75 mg", ["Plavix 75"], "tablet", "75 mg"),
    ("Aspirin 325 mg", ["Bayer"], "tablet", "325 mg"),
    ("Warfarin 2.5 mg", ["Coumadin 2.5"], "tablet", "2.5 mg"),
    ("Warfarin 5 mg", ["Coumadin 5"], "tablet", "5 mg"),
    ("Levothyroxine 25 mcg", ["Synthroid 25"], "tablet", "25 mcg"),
    ("Levothyroxine 75 mcg", ["Synthroid 75"], "tablet", "75 mcg"),
    ("Levothyroxine 100 mcg", ["Synthroid 100"], "tablet", "100 mcg"),
    ("Levothyroxine 125 mcg", ["Synthroid 125"], "tablet", "125 mcg"),
    ("Insulin aspart", ["NovoLog"], "injection", ""),
    ("Insulin detemir", ["Levemir"], "injection", ""),
    ("Semaglutide", ["Ozempic", "Wegovy"], "injection", ""),
    ("Tirzepatide", ["Mounjaro", "Zepbound"], "injection", ""),
    ("Dulaglutide", ["Trulicity"], "injection", ""),
    ("Liraglutide", ["Victoza"], "injection", ""),
    ("Canagliflozin", ["Invokana"], "tablet", "100 mg"),
    ("Linagliptin", ["Tradjenta"], "tablet", "5 mg"),
    ("Pioglitazone", ["Actos"], "tablet", "15 mg"),
    ("Glimepiride", ["Amaryl"], "tablet", "2 mg"),
    ("Gliclazide MR", ["Diamicron MR"], "tablet", "30 mg"),
    ("Hydroxychloroquine", ["Plaquenil"], "tablet", "200 mg"),
    ("Methotrexate", ["Trexall"], "tablet", "2.5 mg"),
    ("Sulfasalazine", ["Azulfidine"], "tablet", "500 mg"),
    ("Azathioprine", ["Imuran"], "tablet", "50 mg"),
    ("Mycophenolate mofetil", ["CellCept"], "capsule", "250 mg"),
    ("Tacrolimus", ["Prograf"], "capsule", "1 mg"),
    ("Cyclosporine", ["Neoral"], "capsule", "100 mg"),
    ("Prednisolone", ["Orapred"], "syrup", ""),
    ("Budesonide nasal", ["Rhinocort"], "nasal spray", ""),
    ("Ipratropium", ["Atrovent"], "inhaler", ""),
    ("Theophylline", ["Theo-24"], "tablet", ""),
    ("Acetylcysteine", ["Mucomyst", "NAC"], "solution", ""),
    ("Guaifenesin-codeine", ["Cheratussin"], "syrup", ""),
    ("Benzonatate", ["Tessalon"], "capsule", "100 mg"),
    ("Mupirocin", ["Bactroban"], "ointment", ""),
    ("Clindamycin topical", ["Cleocin T"], "gel", ""),
    ("Tretinoin", ["Retin-A"], "cream", ""),
    ("Adapalene", ["Differin"], "gel", ""),
    ("Benzoyl peroxide", ["PanOxyl"], "gel", ""),
    ("Hydrocortisone 1%", ["Cortaid"], "cream", "1%"),
    ("Clotrimazole cream", ["Lotrimin"], "cream", ""),
    ("Terbinafine cream", ["Lamisil AT"], "cream", ""),
    ("Nystatin oral", ["Mycostatin"], "suspension", ""),
    ("Ketoconazole shampoo", ["Nizoral"], "shampoo", ""),
    ("Permethrin cream", ["Elimite"], "cream", "5%"),
    ("Ivermectin cream", ["Soolantra"], "cream", ""),
    ("Latanoprost", ["Xalatan"], "eye drops", ""),
    ("Timolol eye drops", ["Timoptic"], "eye drops", ""),
    ("Olopatadine", ["Pataday", "Patanol"], "eye drops", ""),
    ("Ketorolac eye drops", ["Acular"], "eye drops", ""),
    ("Ofloxacin ear", ["Floxin Otic"], "ear drops", ""),
    ("Ciprofloxacin-dexamethasone ear", ["Ciprodex"], "ear drops", ""),
    ("Neomycin-polymyxin-HC", ["Cortisporin"], "ear drops", ""),
    ("Artificial tears", ["Refresh", "Systane"], "eye drops", ""),
    ("Naloxone nasal", ["Narcan"], "nasal spray", ""),
    ("Epinephrine auto-injector", ["EpiPen", "Auvi-Q"], "injection", ""),
    ("Glucagon", ["Baqsimi", "GlucaGen"], "injection / nasal", ""),
    ("Nitroglycerin sublingual", ["Nitrostat"], "tablet", "0.4 mg"),
    ("Isosorbide mononitrate", ["Imdur"], "tablet", "30 mg"),
    ("Digoxin", ["Lanoxin"], "tablet", "0.125 mg"),
    ("Amiodarone", ["Pacerone"], "tablet", "200 mg"),
    ("Diltiazem ER", ["Cardizem CD"], "capsule", "120 mg"),
    ("Verapamil ER", ["Calan SR"], "tablet", "120 mg"),
    ("Nifedipine ER", ["Procardia XL"], "tablet", "30 mg"),
    ("Hydralazine", ["Apresoline"], "tablet", "25 mg"),
    ("Clonidine", ["Catapres"], "tablet", "0.1 mg"),
    ("Doxazosin", ["Cardura"], "tablet", "2 mg"),
    ("Terazosin", ["Hytrin"], "capsule", "2 mg"),
    ("Prazosin", ["Minipress"], "capsule", "1 mg"),
    ("Sacubitril-valsartan", ["Entresto"], "tablet", "24/26 mg"),
    ("Dapagliflozin HF", ["Farxiga HF"], "tablet", "10 mg"),
    ("Empagliflozin HF", ["Jardiance HF"], "tablet", "10 mg"),
    ("Ivabradine", ["Corlanor"], "tablet", "5 mg"),
    ("Eplerenone", ["Inspra"], "tablet", "25 mg"),
    ("Torsemide", ["Demadex"], "tablet", "20 mg"),
    ("Bumetanide", ["Bumex"], "tablet", "1 mg"),
    ("Metolazone", ["Zaroxolyn"], "tablet", "2.5 mg"),
    ("Chlorthalidone", ["Thalitone"], "tablet", "25 mg"),
    ("Indapamide", ["Lozol"], "tablet", "1.25 mg"),
    ("Triamterene-HCTZ", ["Dyazide", "Maxzide"], "capsule", ""),
    ("Potassium citrate", ["Urocit-K"], "tablet", ""),
    ("Tamsulosin 0.4 mg", ["Flomax 0.4"], "capsule", "0.4 mg"),
    ("Dutasteride", ["Avodart"], "capsule", "0.5 mg"),
    ("Alfuzosin", ["Uroxatral"], "tablet", "10 mg"),
    ("Silodosin", ["Rapaflo"], "capsule", "8 mg"),
    ("Oxybutynin ER", ["Ditropan XL"], "tablet", "10 mg"),
    ("Tolterodine", ["Detrol"], "tablet", "2 mg"),
    ("Solifenacin", ["Vesicare"], "tablet", "5 mg"),
    ("Fesoterodine", ["Toviaz"], "tablet", "4 mg"),
    ("Vibegron", ["Gemtesa"], "tablet", "75 mg"),
    ("Sildenafil 100 mg", ["Viagra 100"], "tablet", "100 mg"),
    ("Tadalafil 20 mg", ["Cialis 20"], "tablet", "20 mg"),
    ("Vardenafil", ["Levitra"], "tablet", "10 mg"),
    ("Alprostadil", ["MUSE", "Caverject"], "pellet / injection", ""),
    ("Medroxyprogesterone acetate", ["Provera", "Depo-Provera"], "tablet / injection", ""),
    ("Norethindrone", ["Aygestin"], "tablet", "5 mg"),
    ("Levonorgestrel IUD", ["Mirena", "Kyleena"], "device", ""),
    ("Etonogestrel implant", ["Nexplanon"], "implant", ""),
    ("Ethinyl estradiol norgestimate", ["Ortho Tri-Cyclen", "Sprintec"], "tablet", ""),
    ("Drospirenone ethinyl estradiol", ["Yaz", "Yasmin"], "tablet", ""),
    ("Ulipristal", ["Ella"], "tablet", "30 mg"),
    ("Levonorgestrel 1.5 mg", ["Plan B One-Step"], "tablet", "1.5 mg"),
    ("Misoprostol GI", ["Cytotec"], "tablet", "200 mcg"),
    ("Pantoprazole IV", ["Protonix IV"], "injection", "40 mg"),
    ("Ondansetron ODT", ["Zofran ODT"], "tablet", "4 mg"),
    ("Promethazine", ["Phenergan"], "tablet", "25 mg"),
    ("Prochlorperazine", ["Compazine"], "tablet", "5 mg"),
    ("Metoclopramide", ["Reglan"], "tablet", "10 mg"),
    ("Dicyclomine", ["Bentyl"], "capsule", "10 mg"),
    ("Hyoscyamine", ["Levsin"], "tablet", "0.125 mg"),
    ("Mesalamine", ["Lialda", "Pentasa"], "tablet", ""),
    ("Budesonide EC", ["Entocort"], "capsule", "3 mg"),
    ("Infliximab", ["Remicade"], "infusion", ""),
    ("Adalimumab", ["Humira"], "injection", ""),
    ("Ustekinumab", ["Stelara"], "injection", ""),
    ("Vedolizumab", ["Entyvio"], "infusion", ""),
    ("Rifaximin", ["Xifaxan"], "tablet", "550 mg"),
    ("Eluxadoline", ["Viberzi"], "tablet", "100 mg"),
    ("Linaclotide", ["Linzess"], "capsule", "145 mcg"),
    ("Lubiprostone", ["Amitiza"], "capsule", "24 mcg"),
    ("Plecanatide", ["Trulance"], "tablet", "3 mg"),
    ("Lactulose", ["Enulose"], "syrup", ""),
    ("Rifaximin HE", ["Xifaxan HE"], "tablet", "550 mg"),
    ("Spironolactone ascites", ["Aldactone"], "tablet", "100 mg"),
    ("Ursodiol", ["Actigall", "Urso"], "capsule", "300 mg"),
    ("Pancrelipase", ["Creon", "Zenpep"], "capsule", ""),
    ("Lactase", ["Lactaid"], "tablet", ""),
    ("Simethicone", ["Gas-X"], "tablet", "125 mg"),
    ("Bismuth subsalicylate", ["Pepto-Bismol"], "tablet", ""),
    ("Loperamide-simethicone", ["Imodium Multi-Symptom"], "tablet", ""),
    ("Oral rehydration salts", ["ORS", "Pedialyte", "Soro de reidratação"], "powder / solution", ""),
    ("Zinc sulfate", ["Zinc diarrhea"], "tablet", "20 mg"),
    ("Vitamin A", ["Retinol"], "capsule", ""),
    ("Vitamin E", ["Tocopherol"], "capsule", ""),
    ("Vitamin K", ["Phytonadione", "Mephyton"], "tablet", "5 mg"),
    ("Thiamine", ["Vitamin B1"], "tablet", "100 mg"),
    ("Niacin", ["Vitamin B3", "Niaspan"], "tablet", ""),
    ("Biotin", ["Vitamin B7"], "tablet", ""),
    ("Omega-3 acid ethyl esters", ["Lovaza"], "capsule", ""),
    ("Icosapent ethyl", ["Vascepa"], "capsule", "1 g"),
    ("Ezetimibe-simvastatin", ["Vytorin"], "tablet", ""),
    ("Alirocumab", ["Praluent"], "injection", ""),
    ("Evolocumab", ["Repatha"], "injection", ""),
    ("Inclisiran", ["Leqvio"], "injection", ""),
    ("Bempedoic acid", ["Nexletol"], "tablet", "180 mg"),
    ("Fenofibrate", ["Tricor"], "tablet", "145 mg"),
    ("Gemfibrozil", ["Lopid"], "tablet", "600 mg"),
    ("Niacin ER", ["Niaspan"], "tablet", "500 mg"),
    ("Colesevelam", ["Welchol"], "tablet", "625 mg"),
    ("Cholestyramine", ["Questran"], "powder", ""),
]

for row in ENGLISH:
    add(*row)

# Common LATAM brands as primary names (map to INN in aliases)
BRANDS = [
    ("Novalgina", ["Dipirona", "Metamizole"], "tablet / drops", "500 mg"),
    ("Tylenol", ["Paracetamol", "Acetaminophen"], "tablet", "750 mg"),
    ("Dorflex", ["Orfenadrina", "Dipirona", "Cafeína"], "tablet", ""),
    ("Neosaldina", ["Dipirona", "Tensaldin"], "tablet", ""),
    ("Buscopan", ["Escopolamina", "Hyoscine"], "tablet", "10 mg"),
    ("Luftal", ["Simeticona"], "drops", ""),
    ("Glifage", ["Metformina"], "tablet", "850 mg"),
    ("Puran T4", ["Levotiroxina"], "tablet", "50 mcg"),
    ("Selozok", ["Metoprolol"], "tablet", "50 mg"),
    ("Aradois", ["Losartana"], "tablet", "50 mg"),
    ("Pantozol", ["Pantoprazol"], "tablet", "40 mg"),
    ("Clavulin", ["Amoxicilina clavulanato"], "tablet / syrup", ""),
    ("Zitromax", ["Azitromicina"], "tablet", "500 mg"),
    ("Bactrim", ["Sulfametoxazol trimetoprima"], "tablet", ""),
    ("Flagyl", ["Metronidazol"], "tablet", "400 mg"),
    ("Cataflam", ["Diclofenaco"], "tablet", "50 mg"),
    ("Voltaren", ["Diclofenaco"], "gel / tablet", ""),
    ("Advil", ["Ibuprofeno"], "tablet", "400 mg"),
    ("Alivium", ["Ibuprofeno"], "suspension / tablet", ""),
    ("Meticorten", ["Prednisona"], "tablet", "20 mg"),
    ("Decadron", ["Dexametasona"], "tablet / elixir", ""),
    ("Aerolin", ["Salbutamol"], "inhaler", ""),
    ("Singulair", ["Montelucaste"], "tablet", "10 mg"),
    ("Claritin", ["Loratadina"], "tablet", "10 mg"),
    ("Allegra", ["Fexofenadina"], "tablet", "180 mg"),
    ("Desalex", ["Desloratadina"], "tablet", "5 mg"),
    ("Rivotril", ["Clonazepam"], "tablet", "0.5 mg"),
    ("Prozac", ["Fluoxetina"], "capsule", "20 mg"),
    ("Zoloft", ["Sertralina"], "tablet", "50 mg"),
    ("Ritalina", ["Metilfenidato"], "tablet", "10 mg"),
    ("Venvanse", ["Lisdexanfetamina"], "capsule", "30 mg"),
    ("Ozempic", ["Semaglutida"], "injection", ""),
    ("Jardiance", ["Empagliflozina"], "tablet", "10 mg"),
    ("Xarelto", ["Rivaroxabana"], "tablet", "20 mg"),
    ("Eliquis", ["Apixabana"], "tablet", "5 mg"),
    ("Plavix", ["Clopidogrel"], "tablet", "75 mg"),
    ("Lasix", ["Furosemida"], "tablet", "40 mg"),
    ("Norvasc", ["Anlodipino"], "tablet", "5 mg"),
    ("Cozaar", ["Losartana"], "tablet", "50 mg"),
    ("Lipitor", ["Atorvastatina"], "tablet", "20 mg"),
    ("Crestor", ["Rosuvastatina"], "tablet", "10 mg"),
    ("Zocor", ["Sinvastatina"], "tablet", "20 mg"),
    ("Nexium", ["Esomeprazol"], "tablet", "40 mg"),
    ("Motilium", ["Domperidona"], "tablet", "10 mg"),
    ("Plasil", ["Metoclopramida"], "drops / tablet", ""),
    ("Dramin", ["Dimenidrinato"], "tablet", "50 mg"),
    ("Floratil", ["Saccharomyces boulardii"], "capsule", ""),
    ("Addera D3", ["Vitamina D", "Colecalciferol"], "drops", ""),
    ("Noripurum", ["Ferro"], "drops / tablet", ""),
    ("Cebion", ["Vitamina C"], "tablet", ""),
    ("Redoxon", ["Vitamina C"], "tablet", ""),
    ("Sorine", ["Soro nasal", "Saline"], "spray", ""),
    ("Mucosolvan", ["Ambroxol"], "syrup", ""),
    ("Fluimucil", ["Acetilcisteína"], "sachet", "600 mg"),
    ("Benegrip", ["Paracetamol combo"], "tablet", ""),
    ("Cimegripe", ["Paracetamol combo"], "tablet", ""),
    ("Resfenol", ["Paracetamol combo"], "capsule", ""),
    ("Torsilax", ["Carisoprodol combo"], "tablet", ""),
    ("Miosan", ["Ciclobenzaprina"], "tablet", "5 mg"),
    ("Miosan", ["Cyclobenzaprine"], "tablet", "10 mg"),
    ("Doril", ["AAS cafeína"], "tablet", ""),
    ("AAS", ["Ácido acetilsalicílico"], "tablet", "100 mg"),
    ("Hipoglós", ["Zinc oxide diaper"], "ointment", ""),
    ("Nebacetin", ["Neomicina bacitracina"], "ointment", ""),
    ("Pantogar", ["Hair vitamin"], "capsule", ""),
    ("Puran", ["Levotiroxina"], "tablet", ""),
    ("Euthyrox", ["Levotiroxina"], "tablet", "50 mcg"),
    ("Medley amoxicilina", ["Amoxicilina"], "capsule", "500 mg"),
    ("EMS dipirona", ["Dipirona"], "tablet", "500 mg"),
    ("Eurofarma losartana", ["Losartana"], "tablet", "50 mg"),
    ("Germed omeprazol", ["Omeprazol"], "capsule", "20 mg"),
    ("Sandoz anlodipino", ["Anlodipino"], "tablet", "5 mg"),
    ("Legrand metformina", ["Metformina"], "tablet", "850 mg"),
    ("Prati-Donaduzzi sinvastatina", ["Sinvastatina"], "tablet", "20 mg"),
    ("Aché enalapril", ["Enalapril"], "tablet", "10 mg"),
    ("Biolab carvedilol", ["Carvedilol"], "tablet", "12.5 mg"),
    ("Hypera ibuprofeno", ["Ibuprofeno"], "tablet", "400 mg"),
    ("Sanofi ramipril", ["Ramipril"], "tablet", "5 mg"),
    ("Pfizer atorvastatina", ["Atorvastatina"], "tablet", "20 mg"),
    ("Bayer ciprofloxacino", ["Ciprofloxacino"], "tablet", "500 mg"),
    ("GSK amoxi-clav", ["Clavulin"], "tablet", ""),
    ("Novartis valsartana", ["Valsartana"], "tablet", "160 mg"),
    ("AstraZeneca rosuvastatina", ["Rosuvastatina"], "tablet", "10 mg"),
    ("Boehringer empagliflozina", ["Jardiance"], "tablet", "10 mg"),
    ("Novo Nordisk semaglutida", ["Ozempic"], "injection", ""),
    ("Lilly tirzepatida", ["Mounjaro"], "injection", ""),
    ("Carisoprodol", ["Soma", "Torsilax"], "tablet", "200 mg"),
    ("Ciclobenzaprina", ["Cyclobenzaprine", "Miosan", "Flexeril"], "tablet", "5 mg"),
    ("Nimesulide", ["Nimesulida"], "tablet", "100 mg"),
    ("Ketoprofen", ["Cetoprofeno"], "tablet", "100 mg"),
    ("Dexketoprofen", ["Dexketoprofeno", "Enantyum"], "tablet", "25 mg"),
    ("Dexketoprofeno", ["Enantyum", "Ketesse"], "tablet", "25 mg"),
    ("Etoricoxibe", ["Etoricoxib", "Arcoxia"], "tablet", "90 mg"),
    ("Etoricoxib", ["Arcoxia"], "tablet", "60 mg"),
    ("Aceclofenaco", ["Aceclofenac", "Airtal"], "tablet", "100 mg"),
    ("Tenoxicam", ["Tilatil"], "tablet", "20 mg"),
    ("Indometacina", ["Indomethacin", "Indocid"], "capsule", "25 mg"),
    ("Sulindac", ["Clinoril"], "tablet", "200 mg"),
    ("Piroxicam gel", ["Feldene gel"], "gel", ""),
    ("Capsaicina", ["Capsaicin", "Capsicum"], "cream", ""),
]
for row in BRANDS:
    add(*row)

# Spanish / French common names as aliases-first entries
add("Paracetamol", ["Acetaminofén", "Doliprane", "Efferalgan"], "comprimé", "500 mg")
add("Amoxicilina", ["Amoxicilina", "Clamoxyl"], "cápsula", "500 mg")
add("Ibuprofeno", ["Ibuprofène", "Nurofen"], "comprimé", "400 mg")
add("Metformina", ["Metformine", "Glucophage"], "comprimé", "850 mg")
add("Omeprazol", ["Oméprazole", "Mopral"], "gélule", "20 mg")
add("Losartán", ["Losartan", "Cozaar"], "comprimido", "50 mg")
add("Enalapril", ["Enalapril", "Renitec"], "comprimido", "10 mg")
add("Levotiroxina", ["Lévothyroxine", "Levothyrox"], "comprimido", "50 mcg")
add("Salbutamol", ["Salbutamol", "Ventoline"], "inhalateur", "")
add("Doliprane", ["Paracetamol"], "comprimé", "1000 mg")
add("Nurofen", ["Ibuprofène", "Ibuprofeno"], "comprimé", "400 mg")
add("Spasfon", ["Phloroglucinol"], "comprimé", "")
add("Phloroglucinol", ["Spasfon"], "tablet", "")
add("Smecta", ["Diosmectite"], "sachet", "")
add("Diosmectite", ["Smecta"], "powder", "")
add("Imodium", ["Loperamida", "Lopéramide"], "gélule", "2 mg")
add("Gaviscon", ["Alginate"], "suspension", "")
add("Kardegic", ["AAS", "Lysine acetylsalicylate"], "sachet", "75 mg")
add("Tahor", ["Atorvastatina"], "comprimé", "20 mg")
add("Coveram", ["Perindopril amlodipine"], "comprimé", "")
add("Perindopril", ["Coversyl", "Aceon"], "tablet", "4 mg")
add("Amlodipino", ["Amlodipine"], "comprimido", "5 mg")
add("Metformina 850", ["Diaformina"], "comprimido", "850 mg")
add("Losartán 50", ["Losacor"], "comprimido", "50 mg")
add("Enalapril 10", ["Lotrial"], "comprimido", "10 mg")
add("Ibuprofeno 600", ["Actron", "Ibupirac"], "comprimido", "600 mg")
add("Diclofenac", ["Voltaren", "Dioxaflex"], "comprimido", "50 mg")
add("Amoxidal", ["Amoxicilina"], "cápsula", "500 mg")
add("Tafirol", ["Paracetamol"], "comprimido", "1 g")
add("Sertal", ["Paracetamol combo"], "comprimido", "")
add("Buscapina", ["Hioscina", "Buscopan"], "comprimido", "")
add("Geniol", ["Paracetamol"], "comprimido", "")
add("Qura", ["Ibuprofeno"], "comprimido", "")
add("Migral", ["Ergotamina combo"], "comprimido", "")
add("Bayaspirina", ["AAS"], "comprimido", "500 mg")
add("Sertal compuesto", ["Paracetamol propifenazona"], "comprimido", "")
add("Tafirol Plus", ["Paracetamol"], "comprimido", "")
add("Loratadina", ["Clarityne"], "comprimido", "10 mg")
add("Desloratadina", ["Aerius"], "comprimido", "5 mg")
add("Montelukast", ["Singulair", "Broncast"], "comprimido", "10 mg")
add("Salbutamol spray", ["Ventolin", "Aerolin"], "inhaler", "")
add("Budesonida spray", ["Budecort"], "inhaler", "")
add("Omeprazol 20", ["Ulcozol"], "cápsula", "20 mg")
add("Pantoprazol 40", ["Pantop", "Tecta"], "comprimido", "40 mg")
add("Ranitidina 150", ["Taural"], "comprimido", "150 mg")
add("Domperidona", ["Peridona"], "comprimido", "10 mg")
add("Metoclopramida", ["Reliveran"], "comprimido", "10 mg")
add("Sulfato ferroso", ["Vitalferro"], "comprimido", "")
add("Ácido fólico 5 mg", ["Folival"], "comprimido", "5 mg")
add("Levotiroxina 50", ["Euthyrox", "T4 Montpellier"], "comprimido", "50 mcg")
add("Metformina 500", ["Diaformina 500"], "comprimido", "500 mg")
add("Glibenclamida 5", ["Euglucon"], "comprimido", "5 mg")
add("Insulina NPH", ["Humulin N", "Insulatard"], "injection", "")
add("Insulina regular", ["Humulin R", "Actrapid"], "injection", "")
add("Losartán HCT", ["Losacor D"], "comprimido", "")
add("Enalapril HCT", ["Lotrial D"], "comprimido", "")
add("Atenolol 50", ["Atenolon"], "comprimido", "50 mg")
add("Carvedilol 12.5", ["Dilatrend"], "comprimido", "12.5 mg")
add("Furosemida 40", ["Lasix"], "comprimido", "40 mg")
add("Espironolactona 25", ["Aldactone"], "comprimido", "25 mg")
add("Sinvastatina 20", ["Zocor"], "comprimido", "20 mg")
add("Atorvastatina 20", ["Zarator"], "comprimido", "20 mg")
add("Rosuvastatina 10", ["Crestor"], "comprimido", "10 mg")
add("Clopidogrel 75", ["Plavix"], "comprimido", "75 mg")
add("AAS 100", ["Aspirin protect", "Cardioaspirina"], "comprimido", "100 mg")
add("Warfarina 5", ["Coumadin"], "comprimido", "5 mg")
add("Rivaroxabán", ["Xarelto"], "comprimido", "20 mg")
add("Apixabán", ["Eliquis"], "comprimido", "5 mg")
add("Omeprazol 40", ["Ulcozol 40"], "cápsula", "40 mg")
add("Esomeprazol 40", ["Nexium"], "comprimido", "40 mg")
add("Lansoprazol 30", ["Lanzopral"], "cápsula", "30 mg")
add("Ranitidina", ["Zantac"], "comprimido", "150 mg")
add("Famotidina", ["Famox"], "comprimido", "20 mg")
add("Sucralfato", ["Sucralfate"], "suspensión", "")
add("Lactulosa", ["Lactulax"], "jarabe", "")
add("Macrogol 3350", ["Muvinlax", "PalaCol"], "polvo", "")
add("Loperamida 2", ["loperin"], "comprimido", "2 mg")
add("Saccharomyces", ["Floratil"], "cápsula", "")
add("Nistatina", ["Micostatin"], "suspensión", "")
add("Fluconazol 150", ["Diflucan"], "cápsula", "150 mg")
add("Itraconazol", ["Sporanox", "Hongoseril"], "cápsula", "100 mg")
add("Terbinafina 250", ["Lamisil"], "comprimido", "250 mg")
add("Aciclovir 400", ["Zovirax"], "comprimido", "400 mg")
add("Valaciclovir", ["Valtrex"], "comprimido", "500 mg")
add("Oseltamivir 75", ["Tamiflu"], "cápsula", "75 mg")
add("Amoxicilina 500", ["Amoxidal 500"], "cápsula", "500 mg")
add("Amoxicilina clavulánico", ["Clavulox", "Augmentin"], "comprimido", "")
add("Azitromicina 500", ["Athromycin", "Zitromax"], "comprimido", "500 mg")
add("Cefalexina 500", ["Keflex", "Cefalexina"], "cápsula", "500 mg")
add("Ciprofloxacina 500", ["Cipro"], "comprimido", "500 mg")
add("Levofloxacina", ["Tavanic"], "comprimido", "500 mg")
add("Doxiciclina 100", ["Vibramicina"], "cápsula", "100 mg")
add("Clindamicina 300", ["Dalacin"], "cápsula", "300 mg")
add("Metronidazol 500", ["Flagyl"], "comprimido", "500 mg")
add("Nitrofurantoína", ["Macrodantoína"], "cápsula", "100 mg")
add("Trimetoprima sulfametoxazol", ["Bactrimel"], "comprimido", "")
add("Prednisona 20", ["Meticorten"], "comprimido", "20 mg")
add("Prednisolona jarabe", ["Prelone"], "jarabe", "")
add("Dexametasona 4", ["Decadron"], "comprimido", "4 mg")
add("Hidrocortisona crema", ["Crema hidrocortisona"], "crema", "1%")
add("Betametasona crema", ["Diprosone"], "crema", "")
add("Mometasona nasal", ["Nasonex"], "spray", "")
add("Fluticasona nasal", ["Flonase", "Flixonase"], "spray", "")
add("Loratadina 10", ["Clarityne"], "comprimido", "10 mg")
add("Cetirizina 10", ["Zyrtec", "Reactine"], "comprimido", "10 mg")
add("Fexofenadina 180", ["Allegra"], "comprimido", "180 mg")
add("Desloratadina 5", ["Aerius"], "comprimido", "5 mg")
add("Difenhidramina", ["Benadryl"], "comprimido", "25 mg")
add("Montelukast 10", ["Singulair"], "comprimido", "10 mg")
add("Salbutamol inhalador", ["Ventolin"], "inhaler", "")
add("Budesonida formoterol", ["Symbicort"], "inhaler", "")
add("Tiotropio", ["Spiriva"], "inhaler", "")
add("Ipratropio", ["Atrovent"], "inhaler", "")
add("Ambroxol jarabe", ["Mucosolvan"], "jarabe", "")
add("Acetilcisteína 600", ["Fluimucil"], "sobre", "600 mg")
add("Soro nasal", ["Suero fisiológico nasal", "Physiomer"], "spray", "")
add("Oximetazolina", ["Afrin", "Nasivin"], "spray", "")
add("Sertralina 50", ["Zoloft", "Altruline"], "comprimido", "50 mg")
add("Fluoxetina 20", ["Prozac"], "cápsula", "20 mg")
add("Escitalopram 10", ["Lexapro", "Cipralex"], "comprimido", "10 mg")
add("Clonazepam 0.5", ["Rivotril"], "comprimido", "0.5 mg")
add("Alprazolam 0.5", ["Xanax", "Alplax"], "comprimido", "0.5 mg")
add("Diazepam 10", ["Valium"], "comprimido", "10 mg")
add("Zolpidem 10", ["Stilnox"], "comprimido", "10 mg")
add("Quetiapina 25", ["Seroquel"], "comprimido", "25 mg")
add("Risperidona 1", ["Risperdal"], "comprimido", "1 mg")
add("Gabapentina 300", ["Neurontin"], "cápsula", "300 mg")
add("Pregabalina 75", ["Lyrica"], "cápsula", "75 mg")
add("Tramadol 50", ["Tramal"], "cápsula", "50 mg")
add("Codeína paracetamol", ["Tylex"], "comprimido", "")
add("Morfina", ["MST"], "comprimido", "")
add("Metilfenidato", ["Ritalina", "Concerta"], "comprimido", "10 mg")
add("Donepezilo", ["Aricept"], "comprimido", "5 mg")
add("Memantina 10", ["Ebixa"], "comprimido", "10 mg")
add("Sildenafil 50", ["Viagra"], "comprimido", "50 mg")
add("Tadalafil 20", ["Cialis"], "comprimido", "20 mg")
add("Tamsulosina", ["Omnic", "Secotex"], "cápsula", "0.4 mg")
add("Finasterida 5", ["Proscar"], "comprimido", "5 mg")
add("Alendronato 70", ["Fosamax"], "comprimido", "70 mg")
add("Alopurinol 100", ["Zyloric"], "comprimido", "100 mg")
add("Colchicina 0.5", ["Colchicina"], "comprimido", "0.5 mg")
add("Carbonato de calcio", ["Calcio"], "comprimido", "500 mg")
add("Vitamina D3", ["Colecalciferol"], "gotas", "")
add("Ácido fólico", ["Ácido fólico"], "comprimido", "5 mg")
add("Sulfato ferroso gotas", ["Hierro"], "gotas", "")
add("Complejo B", ["Neurobionta"], "comprimido", "")
add("Omeprazol + claritromicina + amoxi", ["Triple terapia H. pylori"], "combo", "")


def key_of(name: str) -> str:
    return " ".join(name.casefold().split())


def main() -> None:
    by_name: dict[str, dict] = {}
    for name, aliases, form, strength in RAW:
        name = name.strip()
        if not name:
            continue
        k = key_of(name)
        aliases = [a.strip() for a in aliases if a.strip() and key_of(a) != k]
        entry = by_name.get(k)
        if entry is None:
            by_name[k] = {
                "name": name,
                "aliases": sorted(set(aliases), key=str.casefold),
                "formHint": form,
                "strengthHint": strength,
            }
        else:
            merged = set(entry["aliases"]) | set(aliases)
            entry["aliases"] = sorted(merged, key=str.casefold)
            if form and not entry["formHint"]:
                entry["formHint"] = form
            if strength and not entry["strengthHint"]:
                entry["strengthHint"] = strength

    items = sorted(by_name.values(), key=lambda e: e["name"].casefold())
    alias_count = sum(len(e["aliases"]) for e in items)
    payload = {
        "version": 1,
        "description": "On-device essential catalog (Brazil/LATAM + global INN/brands). Grow this file; do not fetch a live world dump on each keystroke.",
        "entryCount": len(items),
        "aliasCount": alias_count,
        "items": items,
    }
    out = Path(__file__).resolve().parents[1] / "ChekMed" / "MedicationCatalog.json"
    out.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    size_kb = out.stat().st_size / 1024
    print(f"Wrote {out}")
    print(f"entries={len(items)} aliases={alias_count} size={size_kb:.1f} KB")


if __name__ == "__main__":
    main()
