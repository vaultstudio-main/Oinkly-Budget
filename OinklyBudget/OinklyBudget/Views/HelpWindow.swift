import SwiftUI
import AppKit

/// Everything the Help window says. Add or edit a topic here; the window picks it up.
///
/// Text lines: start with "## " for a subheading and "• " for a bullet. Anything else is a paragraph.
/// Screenshots: each topic can list shots by asset name. Add an image set with that exact name to
/// Assets.xcassets and it appears under the text; a shot with no image yet simply doesn't show.
/// The list of shots to take is in help-screenshots.md, in the docs folder next to the project folder.
enum HelpContent {
    struct Shot: Hashable {
        /// Asset catalog name, such as "Help-summary".
        let asset: String
        let caption: String
    }

    struct Topic: Identifiable, Hashable {
        let title: String
        let symbol: String
        let lines: [String]
        var id: String { title }
        /// The pictures under this topic, from `HelpContent.shotsByTopic`.
        var shots: [Shot] { HelpContent.shotsByTopic[title] ?? [] }
    }

    struct Group: Identifiable {
        let title: String
        let topics: [Topic]
        var id: String { title }
    }

    static let groups: [Group] = [
        Group(title: "Start Here", topics: [
            Topic(title: "Welcome", symbol: "hand.wave", lines: [
                "Oinkly Budget keeps your accounts, bills, budgets, goals and investments on your own Mac. There is no account to create and nothing is sent anywhere.",
                "## Your first few minutes",
                "• Add your accounts. The setup screen walks you through it, and Manage Accounts at the bottom of the side panel lets you add more any time.",
                "• Record what happens: File ▸ New Transaction for everyday money in and out, New Credit Card Charge for cards, ATM Withdrawal for cash.",
                "• Add your bills on the Bills & Recurring page so they show on the calendar and remind you.",
                "• Open Summary for the big picture and Reports to see where your money goes.",
                "## Help any time",
                "Press ⇧⌘/ or choose Help ▸ Oinkly Budget Help. Search this window with the field at the top of the list.",
            ]),

            Topic(title: "Finding Your Way", symbol: "sidebar.left", lines: [
                "The side panel stays open on the left. It has two parts.",
                "## Overview",
                "• Summary: your net worth, this month's income and spending, your priority bills, and cards for liabilities, investments, goals and recent transactions.",
                "• Transactions: every account's transactions together, with a search field.",
                "• Reports: where your money goes, with six-month projections.",
                "• Liabilities: everything you owe, how much is paid off, and your leverage.",
                "• Investments: value, growth and contributions across your investment accounts.",
                "• Bills & Recurring: the calendar, what is due this month, and your repeating transactions.",
                "• Planning: your goals, and your loans with estimated payoff dates.",
                "• Budgets: what you set aside for each category, what you spent and what is left.",
                "Go to any of them with ⌘1 to ⌘8, or use the Go menu.",
                "## Accounts",
                "Cash on Hand sits at the top by itself, with your Primary Checking account under it if you chose one. The rest are grouped in folders by type: Checking & Savings, Credit Cards, Mortgages & Loans, Investments and Assets. Click an account to open its register. The side panel shows each account's name and type, never its balance, so nothing private is on show until you open it.",
                "Manage Accounts is pinned at the bottom of the panel.",
                "## The bar at the bottom",
                "The bar along the bottom of every page says what you are looking at. On the right, one dot tells you your data is safe: green Shadow Copy Database · Copied 5 min. ago when everything is saved and your shadow copy is up to date, yellow while something is being written, orange when the shadow copy needs a look (it says Not set up until you set one up), red if saving or copying keeps failing. Click it to open the settings.",
            ]),
        

            Topic(title: "The Status Bar", symbol: "dot.circle", lines: [
                "The bar along the bottom of every page says what you are looking at on the left, such as 134 transactions · October 2026.",
                "On the right, one dot and a few words tell you your data is safe. It covers both the database on this Mac and your shadow copy. Click it to open Settings ▸ Data & Backup.",
                "• Green, Shadow Copy Database · Copied 5 min. ago: everything is written to your Mac and your shadow copy is up to date.",
                "• Yellow, Saving… or Copying…: a change was just made and is being written. It turns green again in a moment.",
                "• Orange, Not set up: you haven't set up a shadow copy yet. Click it to choose a folder.",
                "• Orange, Out of date, Folder not found or Other data: the shadow copy needs a look. Out of date means changes have waited a while to be copied. Folder not found means its folder or drive can't be reached. Other data means the folder holds a shadow copy of different data, which was left alone.",
                "• Red, Database · Problem: saving keeps failing. Your changes are still in the app. Save a backup, then restart Oinkly Budget. Hover over the dot to see why.",
                "• Red, Shadow Copy · Problem: copying keeps failing. Your data is not affected.",
                "While you share your data, a separate Shared dot says whether the shared data is saved, and this one shows the shadow copy and only reports a database problem.",
                "Hover over the dot to see when everything was last saved and copied.",
            ]),

            Topic(title: "Using Help", symbol: "questionmark.circle", lines: [
                "Help lives in the Help menu. Choose Oinkly Budget Help, or press ⇧⌘/.",
                "• Topics are grouped on the left. Click one to read it, with pictures of the screens it talks about.",
                "• Search Help with the field above the list. It looks through every topic.",
                "• The Help window opens large, and you can resize it.",
            ]),
        ]),

        Group(title: "Accounts", topics: [
            Topic(title: "Adding & Managing Accounts", symbol: "building.columns", lines: [
                "Choose Manage Accounts at the bottom of the side panel (or Oinkly Budget ▸ Settings ▸ Accounts) to add, edit or delete an account.",
                "## What each kind keeps",
                "• Checking, savings and the like: institution, account number and an opening balance. Checking accounts can also keep three routing numbers: ACH, wire (which can include letters) and digital.",
                "• Credit cards: card number, credit limit, APR, minimum payment, payment due date and the balance you owe.",
                "• Loans and mortgages: what it's for, amount borrowed, monthly payment, interest rate, start and maturity dates, and what you owe now.",
                "• Auto accounts can be a loan or a lease, with a photo and VIN.",
                "• Investments: holdings with shares and prices.",
                "• Assets (house, car, valuables): a value and a photo.",
                "## Picture colour",
                "Every account and bill has a small picture. Until you add a photo, the app draws one for you. In Edit Details, choose Picture Colour to pick one of eight colours, or leave it on Automatic to keep the colour that goes with that kind of account. A bill has the same choice in its editor. The colour you pick shows on the account page, in goals and in the bills lists, and it is saved in your backups.",
                "## Primary Checking",
                "In Edit Details, mark one checking account as your primary. It is pinned under Cash on Hand in the side panel and labelled Primary Checking. Only one account can be primary; choosing another one replaces it.",
                "## Good to know",
                "• Account names can be up to 30 characters.",
                "• Account and card numbers show masked (•••• 1234) until you press Show.",
                "• Deleting an account also deletes its transactions and can't be undone. Cash on Hand can't be deleted.",
                "• You can edit a single account from its page with Edit Details, or right-click it in the side panel.",
            ]),

            Topic(title: "Opening Balances", symbol: "plus.circle", lines: [
                "When you give a checking, savings, investment or similar account an opening balance, Oinkly Budget records it as a real transaction: payee Deposit, category Deposit, method Bank Deposit, memo Opening balance, status Reconciled. It is the first line of the register, so the register and the balance always agree.",
                "• It is locked. You can't edit or delete it from the register.",
                "• To change it, open the account's Edit Details and change the opening balance. The Deposit updates, or goes away if you set the balance to zero.",
                "• Cash on Hand has no opening balance. It starts at $0.00 and fills from ATM withdrawals.",
                "• A savings goal that creates its own account records its starting amount the same way.",
            ]),

            Topic(title: "Account Details & Goal Section", symbol: "rectangle.split.2x1", lines: [
                "An account's page opens with its details in even columns: type, institution, balances, account number, this month's activity, and the unreconciled and pending counts with their amounts.",
                "• Loans show the loan facts: original amount, monthly payment, paid off so far, still owed, interest rate, payments left, maturity date, payment due and a progress bar.",
                "• Credit cards show the limit, available credit, APR and minimum payment.",
                "• If a goal follows the account, a Goal section sits beside the details. It looks the same on every kind of account. See Goals.",
            ]),

            Topic(title: "Cash on Hand", symbol: "dollarsign.circle", lines: [
                "Cash on Hand is built in. It is for the cash you carry, so it has no bank details and no opening balance. It starts at $0.00 and is filled by ATM withdrawals.",
                "## ATM Withdrawal",
                "Choose File ▸ ATM Withdrawal… (⇧⌘A). Pick the checking or savings account the cash comes from, the amount and the date. Oinkly Budget takes it out of that account and adds it to Cash on Hand as one linked pair, so it never counts as income or spending.",
                "• Every withdrawal reads the same: payee ATM Withdrawal, category ATM, method Cash, memo Cash, no receipt, always reconciled.",
                "• Those fields are locked on purpose, because that's what cash from an ATM always is.",
                "## Spending and receiving cash",
                "Open the Cash on Hand account and click the blue New Cash Transaction button. It only ever affects Cash on Hand, and the method is always Cash. Pick Spent or Received, then the amount, date, payee, category and memo, and attach a receipt if you have one.",
                "• Cash on Hand isn't offered in New Transaction. Use New Cash Transaction for cash you spend or receive, and ATM Withdrawal for cash you take out of a bank account.",
            ]),

            Topic(title: "Credit Cards", symbol: "creditcard", lines: [
                "Credit cards keep a card number (up to 19 digits), a credit limit, an APR, a minimum payment and a payment due date.",
                "## Charging a card",
                "Choose File ▸ New Credit Card Charge… (⌥⌘N). Pick the card, enter the amount, payee and category. Available credit shows as you type.",
                "• A charge that would reach or pass the credit limit is refused with \"Exceeds Credit Limit\".",
                "• The method is always Credit Card, and you can attach a receipt.",
                "• Credit cards don't appear in New Transaction. Charges go through this form.",
                "## Paying a card",
                "Use Pay a Bill and choose the card under Loans & Cards. The payment comes off the card's balance and out of the account you pay from. A payment on a card never has a receipt.",
                "## Due date",
                "Turn on Set a payment due date when you edit the card, and it appears on the Bills & Recurring page every month for the minimum payment.",
            ]),

            Topic(title: "Loans & Mortgages", symbol: "banknote", lines: [
                "Loans keep what you borrowed, the interest rate, the monthly payment, a start date and a maturity date. Oinkly Budget estimates the payments left until maturity.",
                "• Turn on Set a payment due date and the loan adds its own bill to the Bills & Recurring page, repeating monthly.",
                "• Mark it paid on the Bills tab, or pay it with Pay a Bill, and the loan's page shows this month as Paid.",
                "• A loan's photo is used as the picture on its bill.",
                "• Loans don't appear in New Transaction. They only take payments, through Pay a Bill.",
                "## Auto lease vs loan",
                "On an Auto account choose Loan or Lease. A lease shows the leasing company and lease end date instead of an interest rate.",
            ]),
        ]),

        Group(title: "Everyday Money", topics: [
            Topic(title: "Transactions & Registers", symbol: "list.bullet.rectangle", lines: [
                "Each account has a register: every transaction with a running balance, one month at a time. The month picker at the top moves between months. Loans show everything at once.",
                "## Adding a transaction",
                "Choose File ▸ New Transaction… (⌘N). Pick Payment for money out or Deposit for money in, then the account, amount, date, payee, category, payment method and status. The categories offered match the direction you chose.",
                "• Type a payee you have used before and the category, amount, memo and payment method fill in from last time. Change anything you like.",
                "• New Transaction offers checking, savings and similar accounts. Loans, credit cards and Cash on Hand have their own forms.",
                "## Status colors",
                "The Status column is a click menu: Pending (not final at the bank) is yellow, Unreconciled (not yet matched to a statement) is red, Reconciled (matched) is green.",
                "## Taking a closer look",
                "Double-click a transaction, in a register or on the Transactions page, to open it in its own window with everything about it, including the receipt at a larger size and any tags or split parts. Nothing can change from there. Close it when you're done, or press Edit… to change it. You can keep several open side by side. From there you can also save the one transaction as a PDF.",
                "## Changing a transaction",
                "The register is read-only so nothing changes by accident. Right-click a transaction (or press ⌘E) and choose Edit Transaction… to change its date, payee, category, method, memo, amount, tags or receipt, then Save.",
                "• Right-click ▸ Delete removes a transaction. Deleting one half of a payment or transfer removes the other half too.",
                "• Right-click ▸ Make Recurring… (⇧⌘R) turns a transaction into a repeating one. See Recurring Transactions.",
                "## Locked items",
                "Some things can't be changed, because they're always the same. See Why Can't I Change That?",
            ]),

            Topic(title: "Split Transactions", symbol: "square.split.1x2", lines: [
                "A split puts one payment across several categories, such as a shopping trip that was part groceries and part household.",
                "## Splitting",
                "In New Transaction or Edit Transaction, turn on Split across categories. Give each part a category and an amount. The parts must add up to the total to the cent, and Save stays off until they do. A split has at least two parts, and every part needs a category.",
                "## How it shows",
                "• The register shows one line with the category Split (3), for three parts.",
                "• The detail window lists every part.",
                "• Reports and budgets count each part under its own category, and the total is never counted twice.",
                "• Turn the split off to go back to one category.",
                "Payments to loans and cards, transfers, ATM withdrawals, opening deposits and investment entries can't be split.",
            ]),

            Topic(title: "Tags", symbol: "tag.fill", lines: [
                "Tags are labels you can put on any transaction, such as Vacation or Reimbursable. A transaction can have as many as you like.",
                "• In New Transaction or Edit Transaction, type a tag in the Tags field and press Return. A tag you haven't used before is made on the spot, with a color.",
                "• Tags show as colored chips in the register's Tags column and in the detail window.",
                "• To tag several transactions at once, select them in a register and choose the Tags menu.",
                "• Settings ▸ Tags lets you rename, recolor, merge and delete tags. Deleting a tag only takes the label off. The transactions stay.",
                "Tags belong to the transaction area. The overview pages, Summary and Reports, don't have a tag selector.",
            ]),

            Topic(title: "Receipts & PDF Bills", symbol: "doc.text.viewfinder", lines: [
                "Checking accounts, credit card charges and Cash on Hand can keep a receipt or a PDF of the bill with the transaction.",
                "• In the register, the Receipt column shows Add Receipt, View Receipt or No Receipt.",
                "• Add a photo, or attach a PDF bill. PDFs open in a scrollable viewer.",
                "• Tick No receipt for this transaction when there isn't one, so the register stops asking.",
                "• Edit Transaction can add, replace or remove a receipt.",
                "• Pay a Bill has a Receipt or Bill section, so you can attach the PDF as you pay.",
                "• ATM withdrawals and payments to cards never have a receipt.",
                "• Receipts and photos are the only files the app keeps.",
            ]),

            Topic(title: "Transfers", symbol: "arrow.left.arrow.right", lines: [
                "Move money between your own accounts with File ▸ Transfer… (⇧⌘T). A transfer is one event with two linked entries, so it is never income or spending and doesn't change your reports.",
                "• Credit cards and loans can't be the source or destination. To pay one, use Pay a Bill.",
                "• Moving cash out of a bank account into Cash on Hand is usually an ATM Withdrawal.",
                "• Deleting one half of a transfer deletes the other.",
            ]),

            Topic(title: "Importing a Bank File", symbol: "square.and.arrow.down", lines: [
                "Open an account and choose Import CSV to add a bank's statement saved as a CSV file. Every row goes to that account. PDF statements can't be imported.",
                "## The preview",
                "Nothing is added until you say so. The preview table shows each row with counts of what is new, what is already in Oinkly Budget and what couldn't be read.",
                "## If the columns aren't recognised",
                "Open How this file is read and tell Oinkly Budget:",
                "• whether there is a header row, and the separator (comma, semicolon, tab or bar);",
                "• which column is the date and how dates are written (it warns you when month-first and day-first are both possible);",
                "• which columns are the payee, memo, category and amount, or separate debit and credit columns;",
                "• for credit card files, that positive amounts are charges;",
                "• whether numbers use a comma as the decimal (1.234,56).",
                "## Options",
                "• Skip transactions already in Oinkly Budget.",
                "• Tidy bank text in payee names.",
                "• Fill categories from payees you have used before.",
                "• Save the format under a name, such as Chase checking. It is found automatically next time.",
                "## Afterwards",
                "You see how many were added, skipped as duplicates, left out as unreadable, or had no matching category. Undo removes everything that import added.",
            ]),

            Topic(title: "Exporting & Printing", symbol: "square.and.arrow.up", lines: [
                "Every account page has Print PDF and Export CSV. The Transactions page has them for all accounts.",
                "## The Export sheet",
                "Choose the account (or all accounts), the period (a month, a year, or from a date) and the paper size, then a save panel asks where to put the file.",
                "• The PDF is a statement with a running balance and repeating headers. To print it, open it in Preview and print from there.",
                "• The CSV uses the layout Import CSV reads, so a file you export can be imported again.",
                "• One transaction can be saved as a PDF from its detail window.",
                "## Settings",
                "Settings ▸ General ▸ PDFs sets the default paper size (Automatic follows your region, US Letter or A4) and the style (plain black and grey, or with color accents). The Export sheet starts from them, and you can still change them for one export.",
                "The Summary and Reports pages have no Print PDF button. PDFs are for accounts and transactions.",
            ]),

            Topic(title: "Autofill & Clean Up", symbol: "wand.and.sparkles", lines: [
                "## Autofill",
                "Type a payee you have used before, exactly as before, and the category, amount, memo and payment method fill in from the last time.",
                "## Clean Up",
                "Settings ▸ Clean Up has three tools for tidying what is already there:",
                "• Find and replace payee names across all transactions, with Replace All and Undo Last Change.",
                "• Look-alike payees lists groups of near-duplicates with counts. Merge the ones you select, merge all into one name, or rename one.",
                "• Move a category's transactions: pick one or more custom categories, choose where their transactions go, and optionally delete the old categories. Payments, transfers and ATM withdrawals keep their locked categories.",
            ]),
        ]),

        Group(title: "Bills & Recurring", topics: [
            Topic(title: "The Bills Tab", symbol: "calendar", lines: [
                "Bills & Recurring has two tabs, Bills and Recurring. The Bills tab shows what is due this month on the left, and a calendar and everything you have set up on the right.",
                "## Adding a bill",
                "Press Add a Bill under the calendar. Give it a name, amount, how often it repeats (once, weekly, every two weeks, monthly, every three months, yearly) and the first due date.",
                "• Category: choose where the bill's payments appear in your reports, such as Phone & Internet.",
                "• Important: marks it so it raises a priority alert as it gets close and shows on the Summary.",
                "• Reminders: pick how many days before it's due. Reminders arrive at 9 AM.",
                "• Photo: attach a picture of the bill. A loan's bill uses the loan's photo. Without a photo, choose a Picture Colour for the picture the app draws.",
                "• Notes: anything else you want to remember.",
                "## Ticking bills off",
                "The month's list shows every bill due this month. Click the circle beside a bill to mark that date paid, and again to undo. Click a day on the calendar to see only that day. To record the actual payment, use Pay a Bill instead.",
                "## All Bills",
                "The All Bills card lists every bill you have set up, with the day it comes out (such as The 5th of every month) and the amount. Click one to edit it.",
            ]),

            Topic(title: "Recurring Transactions", symbol: "arrow.triangle.2.circlepath", lines: [
                "A recurring transaction is a rule for something that repeats, such as a paycheque or rent. On each due date it adds a pending transaction for you to confirm.",
                "## Adding a rule",
                "Open the Recurring tab and press Add Recurring, or right-click a transaction in a register and choose Make Recurring… The rule has a payee, account, type, amount, category, payment method, memo, how often it repeats and the first date. It can stop on a date.",
                "• Add a pending transaction automatically: on, the entry is made for you. Off, the rule only reminds you, and the date waits until you add it or skip it.",
                "## The Recurring tab",
                "• The tiles show what comes in and goes out this month from repeating transactions, what is next, and how many rules there are.",
                "• The month's list shows each date. A date waiting for you is added by ticking its circle. An entry a rule made is ticked to confirm it, and ticked again to take that back.",
                "• The calendar has a dot on each date. Click a day to see only that day.",
                "• All Rules lists every rule with the day it comes out and the amount. From there you can edit, skip the next date, pause, resume or delete. Deleting a rule leaves the transactions it already made.",
                "## Where else they show",
                "• In the menu bar pop-up, marked Repeating, and in the number beside the pig.",
                "• In reminders: a notification on the morning of each date, with no amount in it.",
                "• In the widget, with names and dates only.",
                "• In the cash flow forecast on Reports.",
                "If the app has been closed for a long time, it adds only the newest dates it missed, up to twelve.",
            ]),

            Topic(title: "Paying a Bill", symbol: "creditcard.fill", lines: [
                "Choose File ▸ Pay a Bill… (⇧⌘B). One payment does everything at once.",
                "## What to fill in",
                "• From: one of your own money accounts, such as checking, savings or Cash on Hand. Investment accounts are never used to pay bills.",
                "• To: a bill, or a loan or credit card.",
                "• Amount: filled in from the bill or the loan's monthly payment, and you can change it.",
                "• Date, payment method and status. Status starts as Reconciled, because a bill you pay has usually already gone through. Choose Pending if it hasn't.",
                "• Memo starts as \"Monthly payment\" and you can change it.",
                "• Receipt or Bill: attach the PDF or a photo, or tick No receipt.",
                "## What it does",
                "• Takes the money out of the account you chose.",
                "• For a loan or card, takes the same amount off what you owe, and records the payment on both sides with the same method.",
                "• Ticks the bill off for the due date it settles.",
                "• Files a bill under its category so it shows in Reports and budgets.",
                "## Deleting a payment",
                "If you delete a payment that settled a bill, that due date goes back to unpaid.",
            ]),
        ]),

        Group(title: "Planning & Reports", topics: [
            Topic(title: "Categories & Budgets", symbol: "tag", lines: [
                "Categories are split into Expenses and Income. Built-in categories are the same everywhere and can't be renamed or deleted.",
                "• Set a monthly budget on an expense category in Settings ▸ Categories. It appears on the Summary and on the Budgets page.",
                "• The Budgets page lists every category that has a budget: budgeted, spent and left, with a progress bar. Categories with a zero budget are hidden.",
                "• Add Custom Category lets you create your own, as an Expense or as Income. You can rename and delete your own.",
                "• Counts as tax-related: tick it on any category and the tax report follows it. Charity, Healthcare, Taxes and similar starter categories are already ticked for you.",
                "• Payment methods work the same way: add your own in Settings ▸ Payment Methods.",
                "• A transaction only offers categories that fit its direction: expense categories for money out, income categories for money in.",
            ]),

            Topic(title: "Summary", symbol: "square.grid.2x2", lines: [
                "The Summary is your whole picture on one page.",
                "• Three cards at the top: Income & Spending, Liabilities and Investments.",
                "• Priority Bills: your next five important bills that are overdue or due in the next 20 days, soonest first, with the amount and how many days away. Make a bill important when you add or edit it.",
                "• Net Worth Over Time: the last 12 months and the next six.",
                "• The Summary card: your assets and liabilities, account by account.",
                "• Loan progress, savings goals, your last 15 transactions, where your income and spending flow, and top spending categories.",
                "A payment or transfer shows once, on the paying side.",
            ]),

            Topic(title: "Reports", symbol: "chart.bar.xaxis", lines: [
                "Reports are grouped into sections: net worth, cash flow, debt and loans, savings and goals, budgets, spending, income, bills and investments.",
                "• One period button picks the span. Each report totals this month, the last three and six months and the last year side by side.",
                "• Line charts show a dashed six-month projection of where things are heading.",
                "• A card without enough data keeps its size and says what it needs, so the page doesn't jump around.",
                "• Payments to loans and cards, transfers and ATM withdrawals aren't counted as spending.",
                "• Split transactions count each part under its own category.",
            ]),

            Topic(title: "Goals & Planning", symbol: "target", lines: [
                "Planning is where your goals live, with your loans and their estimated payoff dates beside them.",
                "## Making a goal",
                "• Pick Save up or Pay off a debt, and set a target amount and date.",
                "• Link the goal to an account. A savings goal follows a checking or savings balance, and a payoff goal follows a loan or card. Progress then updates by itself: a savings goal counts the balance above where it started, a payoff goal counts how far the balance has come down.",
                "• A goal that isn't linked keeps its own progress. Press Make Progress on its card to add what you set aside or paid.",
                "• Create an account from a savings goal: give it an account number, institution and the amount saved so far, which becomes the account's opening Deposit.",
                "## The Goal section",
                "On a linked account, the Goal section shows the goal's name and target date, whether you're on track, behind, past the date or reached, what you need each month, your pace over the last three months, what it takes to catch up, an estimated finish date, and a progress bar.",
                "• A reached goal is kept with its final amount and stops following the account.",
                "• You can edit or delete a goal at any time.",
                "## Loans",
                "Loans with maturity dates and estimated payoff dates are listed beside the goals, with whether the loan will be paid off before it matures.",
            ]),

            Topic(title: "Liabilities", symbol: "arrow.down.circle", lines: [
                "Liabilities lists everything you owe, how much of each loan is paid off, and your leverage.",
                "• A Paid Down card shows how much you have paid off over three months, six months and a year, with a projection.",
                "• Cards wait for your own data and say what they need until it's there.",
            ]),

            Topic(title: "Investments", symbol: "chart.line.uptrend.xyaxis", lines: [
                "Investment accounts (401(k), IRA, brokerage, 529, crypto and more) hold positions instead of categories.",
                "• Add holdings in the account's Holdings panel with shares and price.",
                "• Keep prices current with File ▸ Update Investment Price… (⌥⌘U).",
                "• Record deposits, withdrawals, gains and fees with a Type instead of a category.",
                "• The Investments page shows value, growth and contributions for three months, six months and a year, and a projection of growth. There is no sample data: cards wait for your own.",
            ]),
        ]),

        Group(title: "Data & Settings", topics: [
            Topic(title: "Backup & Restore", symbol: "externaldrive", lines: [
                "Settings ▸ Data & Backup saves everything to one .pig file and restores it.",
                "## What's in a backup",
                "Accounts, transactions with their splits, tags and receipts, bills, recurring rules, goals, holdings, budgets, your custom categories and payment methods, your own reminders, your saved CSV import formats, and your preferences.",
                "## Saving one",
                "Choose Export Backup and pick where to put the file. Keep backups somewhere safe: anyone with a .pig file can read it. Once you have a very large number of transactions, a reminder on this page and on the Summary suggests saving a backup.",
                "## Restoring",
                "• Choose Restore from Backup, or double-click a .pig file, or use Restore from a Backup on the setup screen.",
                "• Restoring replaces everything currently in the app. First, a copy of what is there now is saved to Application Support ▸ Backups ▸ Before restoring a backup, so a restore can always be undone. If that copy can't be made, the restore doesn't start.",
                "## Erase All Data",
                "Settings ▸ Data & Backup ▸ Erase All Data deletes your accounts, transactions, bills, goals, custom categories and payment methods, then closes the app after a short countdown so you can cancel. Open it again to start fresh. Built-in categories and their budgets stay.",
                "Take a backup before anything you can't undo.",
            ]),

            Topic(title: "Shadow Copy", symbol: "shield.lefthalf.filled", lines: [
                "A shadow copy is a second copy of your data in a folder you choose, such as Documents or iCloud Drive. Oinkly Budget keeps it up to date on its own, so there is always a spare if something goes wrong.",
                "## Setting it up",
                "• After you have added some data, Oinkly Budget offers to set one up. Or go to Settings ▸ Data & Backup ▸ Shadow Copy and choose Choose Folder.",
                "• A folder called Oinkly Budget Shadow Copy is made inside the folder you chose. Please don't edit or move the files in it.",
                "## When it is copied",
                "• A few minutes after you change something, when you hide the app, and when you quit.",
                "• While you share your data, each time the shared data is saved.",
                "• It keeps the latest copy, the ten before it, and one per day for a week.",
                "## The status in the bottom bar",
                "• Green, Shadow · Copied 5 min. ago: the shadow copy is up to date.",
                "• Yellow, Shadow · Copying…: it is being updated.",
                "• Orange: it needs a look. Not set up, Out of date, Folder not found (the drive may be unplugged) or Other data (the folder holds a shadow copy of different data). Click it to open the settings.",
                "• Red, Shadow · Problem: copying keeps failing. Your data is not affected.",
                "## Restoring",
                "• Settings ▸ Data & Backup ▸ Shadow Copy ▸ Restore shows every copy. Choose one, and Oinkly Budget restarts with it. What was there before is kept in Application Support ▸ Backups first.",
                "• If your data is empty, much smaller than the shadow copy, or can't be read when the app starts, it stops and asks before opening anything. You can restore, pick an older copy, or keep your data as it is.",
                "• While you share your data, the same happens when the shared data is missing, damaged, older than your shadow copy, or not the data your shadow copy came from. You can put the shared data back from the shadow copy.",
                "• On a new Mac, the setup screen has Restore from a Shadow Copy. Choose the folder that contains Oinkly Budget Shadow Copy, for example one in iCloud Drive.",
                "## Good to know",
                "• The shadow copy is a plain copy of your data and is not encrypted. Anyone who can open its folder can read it, and a folder in iCloud Drive is also on Apple's servers.",
                "• Erase All Data keeps the shadow copy unless you choose to delete it too, so an erase can still be undone.",
                "• Turn Off stops the copying. What is in the folder stays there.",
            ]),

            Topic(title: "The Safety Copy", symbol: "shield.lefthalf.filled", lines: [
                "The first time Oinkly Budget 1.0 opens your data, it makes a copy of it first, in Application Support ▸ Backups ▸ Before this update. It holds the data file and your receipts exactly as they were.",
                "• Your data stays in the app's own folder. The widget and the menu bar item never move it.",
                "• Everything upgrades by itself. If a data file can't be opened, you see an error screen instead of an empty app, and nothing is replaced.",
                "• The copy stays until you delete it. Once you are happy with the new version, you can delete the Before this update folder to get the space back.",
                "• It is still a good idea to save a .pig backup yourself before you update.",
            ]),

            Topic(title: "The Menu Bar Item", symbol: "menubar.rectangle", lines: [
                "The pig in the menu bar shows what is coming up at a glance, with a number when a bill or a repeating transaction is due within three days.",
                "• Click it for one list for the month: bills and repeating transactions together, soonest first, each marked Bill or Repeating, with the date and how many days away it is.",
                "• Tick a bill to mark it paid. A repeating transaction that waits for you has a plus button to add it now.",
                "• The top shows how many bills are left to pay this month, their total, and the next one due, or how many are overdue.",
                "• Closing the main window leaves the app running so the pig stays. Click the app in the Dock to open the window again, and press ⌘Q to quit.",
                "• Settings ▸ General ▸ Background turns the menu bar item on or off and opens the app when you log in.",
            ]),

            Topic(title: "Reminders", symbol: "bell", lines: [
                "Reminders are notifications from macOS, so they arrive even when Oinkly Budget isn't open. The first time one is planned, macOS asks if it may show notifications.",
                "## Bill reminders",
                "• Each bill sends a notification the number of days you chose before it is due, and another on the day it is due, at 9 AM.",
                "• Turn them off in Settings ▸ Reminders. Send a Test Notification there to check they work, or open the notification settings if macOS has them off.",
                "## Repeating transactions",
                "• A repeating transaction sends a reminder on the morning of each date. It says what is due and never shows an amount.",
                "## Your own reminders",
                "Settings ▸ Reminders ▸ Add a Reminder sets up a notification to do something in the app, such as reviewing your budget on the 1st, checking bills every Monday or backing up each month.",
                "• Choose a ready-made one or write your own, with a message, how often (every day, week, month or once) and the time.",
                "• Choose a page to open when you click the notification.",
                "• Switch a reminder off without deleting it, or delete it when you no longer need it.",
                "• Your reminders are saved with your data, so a backup includes them and a restore brings them back.",
            ]),

            Topic(title: "The Widget", symbol: "rectangle.3.group", lines: [
                "Upcoming Transactions comes in small, medium and large. It lists the same things as the menu bar item, plus your own reminders, in date order and marked Bill, Repeating or Reminder. It shows names and dates only: never an amount, a balance or an account detail.",
                "• Small shows three lines with a day word (Today, Tomorrow, Friday). Medium shows three lines with their markers and a summary. Large shows nine lines, each with the date and how many days away it is.",
                "• Add it from the widget gallery (edit widgets on the desktop or in Notification Center).",
                "• Right-click it and choose Edit Widget to pick all bills or only important ones, how far ahead (this month, 7, 14 or 30 days), and whether repeating transactions and your reminders show.",
                "• It updates after Oinkly Budget saves. If you see Open Oinkly Budget to show what is coming up here, open the app once. It writes the small file the widget reads.",
            ]),

            Topic(title: "Settings", symbol: "gearshape", lines: [
                "Open Settings with Oinkly Budget ▸ Settings… (⌘,).",
                "• General: menu bar and login options, appearance (light, dark or system), currency, and the default paper size and style for PDFs.",
                "• Reminders: bill reminders and your own custom reminders.",
                "• Accounts: add, edit and delete accounts.",
                "• Categories: budgets, tax-related and custom categories.",
                "• Tags: rename, recolor, merge and delete tags.",
                "• Clean Up: find and replace payees, merge look-alikes, move a category's transactions.",
                "• Payment Methods: your own methods.",
                "• Data & Backup: your counts, backups and restore, Erase All Data, and the version.",
            ]),
        ]),

        Group(title: "Reference", topics: [
            Topic(title: "Keyboard Shortcuts", symbol: "keyboard", lines: [
                "## Adding things",
                "• ⌘N  New Transaction",
                "• ⌥⌘N  New Credit Card Charge",
                "• ⇧⌘A  ATM Withdrawal",
                "• ⇧⌘T  Transfer",
                "• ⇧⌘B  Pay a Bill",
                "• ⌥⌘U  Update Investment Price",
                "## With a transaction selected",
                "• ⌘E  Edit Transaction",
                "• ⌘I  View Details",
                "• ⇧⌘R  Make Recurring",
                "## Going to a page (Go menu)",
                "• ⌘1  Summary",
                "• ⌘2  Transactions",
                "• ⌘3  Reports",
                "• ⌘4  Liabilities",
                "• ⌘5  Investments",
                "• ⌘6  Bills & Recurring",
                "• ⌘7  Planning",
                "• ⌘8  Budgets",
                "## Everywhere",
                "• ⌘,  Settings",
                "• ⇧⌘/  This help",
                "• ⌘Q  Quit",
            ]),

            Topic(title: "Accessibility", symbol: "accessibility", lines: [
                "Oinkly Budget works with VoiceOver and keyboard navigation.",
                "• Buttons that are only a picture have spoken labels, and page and card titles are headings you can jump between.",
                "• Everything the right-click menu does on a transaction is also in the Transaction menu with a shortcut, so you never need a mouse.",
                "• Decorative pictures are hidden from VoiceOver.",
                "• The status dots always come with words, such as Database · Saved, so color is never the only signal.",
            ]),

            Topic(title: "Why Can't I Change That?", symbol: "lock", lines: [
                "A few things are locked so the numbers stay right. Here's why.",
                "• The opening Deposit: it is the account's first entry. Change the opening balance in Edit Details instead.",
                "• Category on a payment, transfer or ATM withdrawal: they aren't spending, so they have a fixed label.",
                "• Category on a bill payment: it follows the bill. Change it by editing the bill.",
                "• Method on a card or Cash on Hand: every charge on a card is a card charge, and every entry in Cash on Hand is cash.",
                "• Amount of a payment or transfer: it's shared with the other account. Delete it and enter it again.",
                "• Split parts: they must add up to the total to the cent, so Save stays off until they do.",
                "• Status of an ATM withdrawal: cash comes out at once, so it's always reconciled.",
                "• Receipts on payments to cards and on ATM withdrawals: there isn't one.",
                "• A goal's progress on a linked account: the balance is the truth, so it can't be entered by hand.",
                "• Type of Cash on Hand, and deleting it: it's built in.",
                "• Date in the register: change it from Edit Transaction… so a stray click can't move it.",
            ]),

            Topic(title: "Your Data & Privacy", symbol: "lock.shield", lines: [
                "Everything stays on your Mac. Oinkly Budget has no account, no sign-in and no online sync.",
                "• Account and card numbers show masked until you press Show.",
                "• The side panel never shows balances. They appear once you open an account.",
                "• Reminders and the widget never show amounts. The widget reads a small file with names and dates only.",
                "• Backups are plain files you keep. Store them somewhere safe, since anyone with a .pig file can read it.",
                "• There is no sync between devices. A backup file is how your data moves to another Mac.",
            ]),
        ]),
    ]

    /// The pictures under each topic, by topic title. An asset with no image yet simply doesn't show.
    static let shotsByTopic: [String: [Shot]] = [
        "Welcome": [Shot(asset: "Help-welcome", caption: "The Summary page, with the side panel on the left.")],
        "Finding Your Way": [Shot(asset: "Help-sidebar", caption: "The side panel: Overview, Cash on Hand and account folders.")],
        "The Status Bar": [Shot(asset: "Help-status-bar", caption: "The bar at the bottom of every page, with the saved dot on the right.")],
        "Adding & Managing Accounts": [Shot(asset: "Help-manage-accounts", caption: "Settings ▸ Accounts."),
                                       Shot(asset: "Help-manage-accounts-page", caption: "The Manage Accounts page."),
                                       Shot(asset: "Help-edit-account", caption: "Edit Details for a checking account, with its routing numbers.")],
        "Opening Balances": [Shot(asset: "Help-opening-balance-edit", caption: "The opening balance field in Edit Details.")],
        "Account Details & Goal Section": [Shot(asset: "Help-card-details", caption: "A card's page with limit, available credit, APR and a Goal section."),
                                           Shot(asset: "Help-savings-details", caption: "A savings account with its goal.")],
        "Cash on Hand": [Shot(asset: "Help-cash-page", caption: "The Cash on Hand page with its New Cash Transaction button."),
                         Shot(asset: "Help-atm-withdrawal", caption: "The ATM Withdrawal window."),
                         Shot(asset: "Help-cash-transaction", caption: "The New Cash Transaction window.")],
        "Credit Cards": [Shot(asset: "Help-card-charge", caption: "New Credit Card Charge, showing available credit."),
                         Shot(asset: "Help-card-details", caption: "A card's page.")],
        "Loans & Mortgages": [Shot(asset: "Help-loan-details", caption: "A loan's page: progress, payment due and payments left."),
                              Shot(asset: "Help-mortgage-details", caption: "A mortgage."),
                              Shot(asset: "Help-auto-loan-details", caption: "An auto loan.")],
        "Transactions & Registers": [Shot(asset: "Help-register", caption: "An account register with the status colors, tags and the Receipt column."),
                                     Shot(asset: "Help-transactions", caption: "The Transactions page: every account together, with a search field."),
                                     Shot(asset: "Help-new-transaction", caption: "File ▸ New Transaction."),
                                     Shot(asset: "Help-edit-transaction", caption: "Right-click ▸ Edit Transaction…"),
                                     Shot(asset: "Help-detail-window", caption: "Double-click a transaction for a closer look.")],
        "Split Transactions": [Shot(asset: "Help-split", caption: "The split editor, with what is left to give a category."),
                               Shot(asset: "Help-split-register", caption: "A split transaction in the register."),
                               Shot(asset: "Help-split-detail", caption: "Every part in the detail window.")],
        "Tags": [Shot(asset: "Help-tags", caption: "Tagging a transaction."),
                 Shot(asset: "Help-tags-register", caption: "A tagged transaction in the register."),
                 Shot(asset: "Help-tags-settings", caption: "Settings ▸ Tags.")],
        "Receipts & PDF Bills": [Shot(asset: "Help-receipt", caption: "A transaction with its receipt shown in the detail window.")],
        "Transfers": [Shot(asset: "Help-transfer", caption: "The Transfer window.")],
        "Importing a Bank File": [Shot(asset: "Help-import", caption: "The import preview with its counts and options."),
                                  Shot(asset: "Help-import-mapping", caption: "How this file is read.")],
        "Exporting & Printing": [Shot(asset: "Help-account-toolbar", caption: "An account page's buttons: Import CSV, Export CSV and Print PDF."),
                                 Shot(asset: "Help-export", caption: "The Export sheet for a PDF statement."),
                                 Shot(asset: "Help-export-csv", caption: "The Export sheet for a CSV file.")],
        "Autofill & Clean Up": [Shot(asset: "Help-autofill", caption: "Typing a payee you've used before suggests it."),
                                Shot(asset: "Help-cleanup", caption: "Settings ▸ Clean Up.")],
        "The Bills Tab": [Shot(asset: "Help-bills", caption: "The Bills tab with the month's bills, the calendar and All Bills."),
                          Shot(asset: "Help-new-bill", caption: "The New Bill form."),
                          Shot(asset: "Help-edit-bill", caption: "Editing a bill.")],
        "Recurring Transactions": [Shot(asset: "Help-recurring", caption: "The Recurring tab."),
                                   Shot(asset: "Help-recurring-edit", caption: "The rule editor."),
                                   Shot(asset: "Help-make-recurring", caption: "Make Recurring, filled in from a transaction."),
                                   Shot(asset: "Help-recurring-pending", caption: "A pending entry made by a rule, in the register.")],
        "Paying a Bill": [Shot(asset: "Help-pay-bill", caption: "The Pay a Bill window.")],
        "Categories & Budgets": [Shot(asset: "Help-categories", caption: "Settings ▸ Categories with budgets."),
                                 Shot(asset: "Help-budgets", caption: "The Budgets page.")],
        "Summary": [Shot(asset: "Help-summary", caption: "The top of the Summary."),
                    Shot(asset: "Help-priority-bills", caption: "Priority Bills."),
                    Shot(asset: "Help-summary-lower", caption: "The lower half of the Summary.")],
        "Reports": [Shot(asset: "Help-reports", caption: "Reports, Overview."),
                    Shot(asset: "Help-reports-spending", caption: "The Spending section."),
                    Shot(asset: "Help-reports-net-worth", caption: "The Net Worth section."),
                    Shot(asset: "Help-reports-debt", caption: "The Debt & Loans section.")],
        "Goals & Planning": [Shot(asset: "Help-goals", caption: "The Planning page."),
                             Shot(asset: "Help-goal-edit", caption: "The goal editor with the account link."),
                             Shot(asset: "Help-goal-detail", caption: "A goal's details."),
                             Shot(asset: "Help-goal-section", caption: "The Goal section on an account.")],
        "Liabilities": [Shot(asset: "Help-liabilities", caption: "The Liabilities page.")],
        "Investments": [Shot(asset: "Help-investments", caption: "The Investments page."),
                        Shot(asset: "Help-brokerage", caption: "An investment account with its holdings."),
                        Shot(asset: "Help-update-price", caption: "Update Investment Price.")],
        "Backup & Restore": [Shot(asset: "Help-backup", caption: "Settings ▸ Data & Backup.")],
        "The Menu Bar Item": [Shot(asset: "Help-menu-bar", caption: "The menu bar pop-up.")],
        "Reminders": [Shot(asset: "Help-reminders-settings", caption: "Settings ▸ Reminders.")],
        "The Widget": [Shot(asset: "Help-widget-large", caption: "Large."),
                       Shot(asset: "Help-widget-medium", caption: "Medium."),
                       Shot(asset: "Help-widget-small", caption: "Small.")],
        "Settings": [Shot(asset: "Help-general-settings", caption: "Settings ▸ General."),
                     Shot(asset: "Help-payment-methods", caption: "Settings ▸ Payment Methods.")],
    ]

    static var topics: [Topic] { groups.flatMap(\.topics) }
}

/// Help ▸ OinklyBudget Help. Topics on the left, the text and screenshots on the right.
struct HelpWindow: View {
    @State private var selection: HelpContent.Topic? = HelpContent.topics.first
    @State private var search = ""

    private var groups: [HelpContent.Group] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return HelpContent.groups }
        return HelpContent.groups.compactMap { group in
            let matches = group.topics.filter {
                $0.title.lowercased().contains(query) || $0.lines.contains { $0.lowercased().contains(query) }
            }
            return matches.isEmpty ? nil : HelpContent.Group(title: group.title, topics: matches)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.topics) { topic in
                            Label(topic.title, systemImage: topic.symbol).tag(topic)
                        }
                    }
                }
            }
            .searchable(text: $search, placement: .sidebar, prompt: "Search Help")
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            if let topic = selection ?? groups.first?.topics.first {
                ScrollView {
                    TopicView(topic: topic)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(28)
                }
                .id(topic.id)
            } else {
                ContentUnavailableView.search(text: search)
            }
        }
        .frame(minWidth: 760, minHeight: 500)
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .piggybankScreenshotAction)) { note in
            guard let action = note.userInfo?["action"] as? String, action.hasPrefix("helpTopic:") else { return }
            let title = String(action.dropFirst("helpTopic:".count))
            if let topic = HelpContent.topics.first(where: { $0.title == title }) { selection = topic }
        }
        #endif
    }
}

private struct TopicView: View {
    let topic: HelpContent.Topic

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: topic.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.tint)
                Text(topic.title).font(.largeTitle.bold())
            }
            .padding(.bottom, 4)

            ForEach(Array(topic.lines.enumerated()), id: \.offset) { _, line in
                lineView(line)
            }

            ForEach(topic.shots, id: \.asset) { shot in
                if let image = NSImage(named: shot.asset) {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 640)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                        Text(shot.caption).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        if line.hasPrefix("## ") {
            Text(String(line.dropFirst(3)))
                .font(.title3.weight(.semibold))
                .padding(.top, 10)
        } else if line.hasPrefix("• ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                Text(String(line.dropFirst(2)))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .textSelection(.enabled)
            .padding(.leading, 6)
        } else {
            Text(line)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
